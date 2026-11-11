use crate::common::*;
use crate::link;
use anyhow::{anyhow, Result};
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use mpsp_core::drift::RateConverter;
use mpsp_core::packet::{open, seal, AudioPacket};
use mpsp_core::pairing::{self, TOKEN_LEN};
use serde::Serialize;
use std::collections::HashMap;
use std::io::ErrorKind;
use std::net::{TcpListener, UdpSocket};
use std::path::Path;
use std::sync::mpsc::{channel, Receiver, RecvTimeoutError, Sender};
use std::sync::{Arc, Mutex};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

const GUEST_TIMEOUT: Duration = Duration::from_secs(10); // guests ping every 1 s
const HANDSHAKE_READ_TIMEOUT: Duration = Duration::from_secs(3); // a stray client can't stall pairing for long
const APPROVAL_TIMEOUT: Duration = Duration::from_secs(60);

#[derive(Serialize, Clone, Debug, PartialEq)]
pub struct GuestView { pub id: String, pub name: String }

#[derive(Serialize, Clone, Debug, PartialEq)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum HostEvent {
    /// A fresh single-use pairing link (shown as a QR). Issued again after every pairing attempt.
    PairingLink { link: String },
    /// A device completed the secure handshake and waits for `Host::respond`.
    JoinRequest { id: String, name: String, address: String },
    Guests { guests: Vec<GuestView> },
    Error { message: String },
}

/// Where the host's audio comes from.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AudioSource {
    /// Capture what this computer is playing (Windows WASAPI loopback, Linux monitor source).
    SystemLoopback,
    /// The platform pushes PCM in through [`ExternalSource`] (Android: MediaProjection playback capture).
    External,
    /// No audio at all: pairing and clock sync only (tests).
    None,
}

#[derive(Clone, Copy)]
pub struct HostOptions { pub source: AudioSource }
impl Default for HostOptions { fn default() -> Self { Self { source: AudioSource::SystemLoopback } } }

/// A paired guest. Each has its own session key, so AEAD nonces never collide across guests.
struct GuestEntry { id: String, name: String, key: Key, audio_addr: String, last_seen: Instant }
type Guests = Arc<Mutex<Vec<GuestEntry>>>;
type Pending = Arc<Mutex<HashMap<String, Sender<bool>>>>;

pub struct Host {
    rx: Receiver<HostEvent>,
    tx: Sender<HostEvent>,
    stop: Stop,
    guests: Guests,
    pending: Pending,
    threads: Vec<JoinHandle<()>>,
    port: u16,
    external: Option<Arc<ExternalSource>>,
}

fn emit_guests(guests: &Guests, tx: &Sender<HostEvent>) {
    let list = guests.lock().unwrap().iter().map(|g| GuestView { id: g.id.clone(), name: g.name.clone() }).collect();
    let _ = tx.send(HostEvent::Guests { guests: list });
}

fn load_or_create_host_key(path: &Path) -> Result<snow::Keypair> {
    // TODO(security): move to the OS keystore (DPAPI / Keychain / Keystore); a plain file is a spike shortcut.
    if let Ok(b) = std::fs::read(path) {
        if b.len() == 64 { return Ok(snow::Keypair { private: b[..32].to_vec(), public: b[32..].to_vec() }); }
    }
    let kp = pairing::generate_static_key()?;
    std::fs::write(path, [kp.private.clone(), kp.public.clone()].concat())?;
    Ok(kp)
}

fn bind_tcp_with_retry(port: u16) -> Result<TcpListener> {
    // A just-stopped host may still hold the port for a moment.
    let mut last = None;
    for _ in 0..10 {
        match TcpListener::bind(("0.0.0.0", port)) {
            Ok(l) => return Ok(l),
            Err(e) => { last = Some(e); thread::sleep(Duration::from_millis(200)); }
        }
    }
    Err(anyhow!("cannot listen on port {port}: {}", last.unwrap()))
}

/// TCP pairing and UDP sync share one port number. With a fixed port both must be free (an error says so). With
/// `port` 0 the OS picks the TCP port, and the same number may already be taken for UDP by an unrelated socket, so
/// try again with another port instead of failing.
fn bind_pair(port: u16) -> Result<(TcpListener, UdpSocket)> {
    let attempts = if port == 0 { 50 } else { 1 };
    let mut last_err = None;
    for _ in 0..attempts {
        let listener = bind_tcp_with_retry(port)?;
        let chosen = listener.local_addr()?.port();
        match UdpSocket::bind(("0.0.0.0", chosen)) {
            Ok(udp) => return Ok((listener, udp)),
            Err(e) => last_err = Some(e),
        }
    }
    Err(anyhow!("cannot use port {} for sync: {}", port, last_err.map(|e| e.to_string()).unwrap_or_default()))
}

impl Host {
    /// `port` 0 picks a free port (TCP pairing and UDP sync share the number). `data_dir` stores the host identity.
    pub fn start(lan_ip: &str, port: u16, data_dir: &Path, opts: HostOptions) -> Result<Host> {
        std::fs::create_dir_all(data_dir)?;
        let kp = load_or_create_host_key(&data_dir.join("host_key.bin"))?;
        let (listener, sync_sock) = bind_pair(port)?;
        listener.set_nonblocking(true)?;
        let port = listener.local_addr()?.port();
        sync_sock.set_read_timeout(Some(Duration::from_millis(500)))?;

        let (tx, rx) = channel();
        let (stop, start) = (Stop::default(), Instant::now());
        let guests: Guests = Arc::new(Mutex::new(Vec::new()));
        let pending: Pending = Arc::new(Mutex::new(HashMap::new()));
        let mut host = Host { rx, tx: tx.clone(), stop: stop.clone(), guests: guests.clone(), pending: pending.clone(), threads: vec![], port, external: None };

        host.threads.push(spawn_responder(sync_sock, start, guests.clone(), tx.clone(), stop.clone()));
        match opts.source {
            AudioSource::SystemLoopback => host.threads.push(spawn_audio(start, guests.clone(), stop.clone())?), // on error, Drop of `host` stops the responder
            AudioSource::External => host.external = Some(Arc::new(ExternalSource(Mutex::new(Streamer::new(start, guests.clone())?)))),
            AudioSource::None => {}
        }
        let lan_ip = lan_ip.to_string();
        host.threads.push(thread::spawn(move || pairing_loop(listener, kp, lan_ip, port, guests, pending, tx, stop)));
        Ok(host)
    }

    pub fn port(&self) -> u16 { self.port }
    /// The sink for [`AudioSource::External`] hosts; `None` for the other sources.
    pub fn external_source(&self) -> Option<Arc<ExternalSource>> { self.external.clone() }
    pub fn poll(&self) -> Option<HostEvent> { self.rx.try_recv().ok() }
    pub fn recv_timeout(&self, d: Duration) -> Option<HostEvent> { self.rx.recv_timeout(d).ok() }

    /// Answer a `JoinRequest`.
    pub fn respond(&self, id: &str, allow: bool) {
        if let Some(s) = self.pending.lock().unwrap().remove(id) { let _ = s.send(allow); }
    }

    /// Disconnect a guest immediately (its key is forgotten, so it can no longer ping or receive audio).
    pub fn kick(&self, id: &str) {
        self.guests.lock().unwrap().retain(|g| g.id != id);
        emit_guests(&self.guests, &self.tx);
    }
}

impl Drop for Host {
    fn drop(&mut self) {
        self.stop.set();
        for t in self.threads.drain(..) { let _ = t.join(); }
    }
}

/// Answers authenticated pings from any paired guest (identified by whose key opens the packet), stamping
/// receive (t1) and send (t2) host times. Also drops guests that went silent.
fn spawn_responder(sock: UdpSocket, start: Instant, guests: Guests, tx: Sender<HostEvent>, stop: Stop) -> JoinHandle<()> {
    thread::spawn(move || {
        let (mut buf, mut seq) = ([0u8; 256], 0u32);
        while !stop.is_set() {
            let got = sock.recv_from(&mut buf);
            let t1 = start.elapsed().as_micros() as u64;
            let mut g = guests.lock().unwrap();
            let before = g.len();
            g.retain(|e| e.last_seen.elapsed() < GUEST_TIMEOUT);
            let dropped = g.len() != before;
            let reply = got.ok().and_then(|(n, from)| {
                let (entry, p) = g.iter_mut().find_map(|e| open(&e.key, PING_ID, &buf[..n]).map(|p| (e, p)))?;
                if p.payload.len() != 8 { return None; }
                entry.last_seen = Instant::now();
                let mut pl = p.payload.clone();
                pl.extend_from_slice(&t1.to_le_bytes());
                pl.extend_from_slice(&(start.elapsed().as_micros() as u64).to_le_bytes());
                let r = AudioPacket { seq, host_ts_us: 0, payload: pl };
                seq = seq.wrapping_add(1);
                Some((seal(&entry.key, PONG_ID, &r), from))
            });
            drop(g);
            if let Some((bytes, from)) = reply { let _ = sock.send_to(&bytes, from); }
            if dropped { emit_guests(&guests, &tx); }
        }
    })
}

/// Encodes captured PCM into Opus packets and sends one encrypted copy per guest. Shared by the sound-card
/// capture (Windows/Linux) and the external push path (Android).
struct Streamer { enc: opus::Encoder, pcm: Vec<f32>, seq: u32, sock: UdpSocket, guests: Guests, start: Instant }

impl Streamer {
    fn new(start: Instant, guests: Guests) -> Result<Self> {
        let mut enc = opus::Encoder::new(RATE, opus::Channels::Stereo, opus::Application::LowDelay)?;
        enc.set_bitrate(opus::Bitrate::Bits(128_000))?;
        Ok(Self { enc, pcm: Vec::new(), seq: 0, sock: UdpSocket::bind("0.0.0.0:0")?, guests, start })
    }

    /// `stereo` is interleaved L,R at 48 kHz. Whole 10 ms frames are sent; the remainder waits for the next push.
    fn push(&mut self, stereo: &[f32]) {
        self.pcm.extend_from_slice(stereo);
        while self.pcm.len() >= FRAME * 2 {
            let frame: Vec<f32> = self.pcm.drain(..FRAME * 2).collect();
            let list = self.guests.lock().unwrap();
            if list.is_empty() { continue; }
            let mut out = [0u8; 1500];
            if let Ok(n) = self.enc.encode_float(&frame, &mut out) { // encode once, seal once per guest
                let p = AudioPacket { seq: self.seq, host_ts_us: self.start.elapsed().as_micros() as u64, payload: out[..n].to_vec() };
                for e in list.iter() { let _ = self.sock.send_to(&seal(&e.key, STREAM_ID, &p), &e.audio_addr); }
                self.seq = self.seq.wrapping_add(1);
            }
        }
    }
}

/// Audio pushed in by the platform (Android's capture service) instead of read from a sound card.
pub struct ExternalSource(Mutex<Streamer>);

impl ExternalSource {
    /// `interleaved_stereo`: 16-bit L,R,L,R... at 48 kHz, any length (it is re-chunked into 10 ms frames).
    pub fn push_i16(&self, interleaved_stereo: &[i16]) {
        let f: Vec<f32> = interleaved_stereo.iter().map(|&x| x as f32 / 32768.0).collect();
        self.0.lock().unwrap().push(&f);
    }
}

/// Captures what this computer plays (the default output device, looped back). The cpal stream is not `Send` on
/// every platform, so it lives (and dies) on its own thread. That thread also watches the default output: a stream
/// stays on the device it opened on, so when the user connects or disconnects Bluetooth headphones (Windows makes
/// them the new default without any error) we reopen the capture on the new default, or the guests would hear
/// silence from the old device.
fn spawn_audio(start: Instant, guests: Guests, stop: Stop) -> Result<JoinHandle<()>> {
    let (ready_tx, ready_rx) = channel::<Result<()>>();
    let h = thread::spawn(move || {
        // One streamer for the whole session: its sequence numbers must keep counting across device switches,
        // otherwise guests would discard the restarted numbers as old packets.
        let streamer = match Streamer::new(start, guests) {
            Ok(s) => Arc::new(Mutex::new(s)),
            Err(e) => { let _ = ready_tx.send(Err(e)); return; }
        };
        let open_capture = |streamer: &Arc<Mutex<Streamer>>| -> Result<(cpal::Stream, String)> {
            let dev = cpal::default_host().default_output_device().ok_or_else(|| anyhow!("no audio output device to capture"))?;
            let (cfg, rate) = output_config(&dev)?; // output config => WASAPI loopback capture
            let name = dev.name().unwrap_or_default();
            let ch = cfg.channels as usize;
            let st = streamer.clone();
            let mut stereo: Vec<f32> = Vec::new();
            // The encoder needs 48 kHz; a device at another rate (Bluetooth at 44.1 kHz) is converted on the way in.
            let mut converter = if rate != RATE { Some(RateConverter::new(rate)) } else { None };
            let stream = dev.build_input_stream(&cfg, move |data: &[f32], _| {
                stereo.clear();
                for f in data.chunks(ch) {
                    stereo.push(f[0]);
                    stereo.push(if ch > 1 { f[1] } else { f[0] });
                }
                match converter.as_mut() {
                    Some(conv) => conv.push(&stereo, FRAME, |chunk| st.lock().unwrap().push(chunk)),
                    None => st.lock().unwrap().push(&stereo),
                }
            }, |e| eprintln!("capture error: {e}"), None)?;
            stream.play()?;
            Ok((stream, name))
        };
        match open_capture(&streamer) {
            Err(e) => { let _ = ready_tx.send(Err(e)); }
            Ok((first, name)) => {
                let _ = ready_tx.send(Ok(()));
                let (mut stream, mut opened_on) = (Some(first), name);
                let mut retry_at: Option<Instant> = None;
                let mut last_check = Instant::now();
                while !stop.is_set() {
                    thread::sleep(Duration::from_millis(50));
                    if stream.is_some() && last_check.elapsed() >= Duration::from_secs(1) {
                        last_check = Instant::now();
                        if output_device_changed(&opened_on, default_output_name().as_deref()) {
                            drop(stream.take());
                            retry_at = Some(Instant::now() + Duration::from_millis(300)); // let the OS finish switching
                        }
                    }
                    if stream.is_none() && retry_at.is_some_and(|t| Instant::now() >= t) {
                        match open_capture(&streamer) {
                            Ok((s, n)) => { stream = Some(s); opened_on = n; retry_at = None; }
                            Err(_) => retry_at = Some(Instant::now() + Duration::from_secs(1)), // keep trying; sharing stays up
                        }
                    }
                }
                drop(stream);
            }
        }
    });
    ready_rx.recv().map_err(|_| anyhow!("audio thread died"))??;
    Ok(h)
}

#[allow(clippy::too_many_arguments)]
fn pairing_loop(listener: TcpListener, kp: snow::Keypair, lan_ip: String, port: u16, guests: Guests, pending: Pending, tx: Sender<HostEvent>, stop: Stop) {
    let mut counter = 0u32;
    while !stop.is_set() {
        let token: [u8; TOKEN_LEN] = pairing::random_bytes();
        let _ = tx.send(HostEvent::PairingLink { link: link::build(&lan_ip, port, &kp.public, &token) });
        let (mut s, peer) = loop {
            match listener.accept() {
                Ok(x) => break x,
                Err(e) if e.kind() == ErrorKind::WouldBlock => {
                    if stop.is_set() { return; }
                    thread::sleep(Duration::from_millis(100));
                }
                Err(e) => { let _ = tx.send(HostEvent::Error { message: format!("pairing listener failed: {e}") }); return; }
            }
        };
        if s.set_nonblocking(false).is_err() || s.set_read_timeout(Some(HANDSHAKE_READ_TIMEOUT)).is_err() { continue; }
        counter += 1;
        let id = format!("g{counter}");
        let res = pairing::host_pair(&mut s, &kp.private, &token, |g| {
            let (atx, arx) = channel();
            pending.lock().unwrap().insert(id.clone(), atx);
            let _ = tx.send(HostEvent::JoinRequest { id: id.clone(), name: g.name.clone(), address: peer.ip().to_string() });
            let deadline = Instant::now() + APPROVAL_TIMEOUT;
            let answer = loop {
                match arx.recv_timeout(Duration::from_millis(200)) {
                    Ok(v) => break v,
                    Err(RecvTimeoutError::Timeout) if !stop.is_set() && Instant::now() < deadline => {}
                    Err(_) => break false,
                }
            };
            pending.lock().unwrap().remove(&id);
            answer
        });
        // A failed attempt (bad token, impostor guest, denial) needs no event: the loop just issues a new link.
        if let Ok((key, g)) = res {
            let audio_addr = format!("{}:{}", peer.ip(), g.audio_port);
            {
                let mut list = guests.lock().unwrap();
                list.retain(|e| e.audio_addr != audio_addr); // same device re-pairing replaces its old entry
                list.push(GuestEntry { id, name: g.name, key, audio_addr, last_seen: Instant::now() });
            }
            emit_guests(&guests, &tx);
        }
    }
}
