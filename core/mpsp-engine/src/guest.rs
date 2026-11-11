use crate::common::*;
use crate::link;
use crate::platform_audio;
use anyhow::{anyhow, Result};
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use mpsp_core::clock::ClockSync;
use mpsp_core::drift::Playout;
use mpsp_core::jitter::{JitterBuffer, Pop};
use mpsp_core::packet::{open, seal, AudioPacket};
use mpsp_core::pairing;
use serde::Serialize;
use std::io::Write;
use std::net::{TcpStream, ToSocketAddrs, UdpSocket};
use std::sync::atomic::{AtomicBool, AtomicI64, AtomicU64, Ordering};
use std::sync::mpsc::{channel, Receiver, Sender};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};

const HOST_SILENCE_LIMIT: Duration = Duration::from_secs(5);
/// An output stream whose callback has not run for this long is considered dead and gets reopened.
const STREAM_STALL_MS: u64 = 1500;

#[derive(Serialize, Clone, Copy, Debug, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum GuestPhase { Pairing, AwaitingApproval, Connected, Error }

#[derive(Serialize, Clone, Debug)]
pub struct GuestStatus {
    pub phase: GuestPhase,
    pub message: String,
    pub rtt_us: Option<i64>,
    pub fill_frames: Option<usize>,
    pub drift_ppm: Option<f64>,
    pub underruns: u64,
    /// Packets that arrived after their playout time, packets given up as lost (concealed), and the worst
    /// lateness seen since the previous status. These tell network jitter apart from clock drift.
    pub late_packets: u64,
    pub lost_packets: u64,
    /// Audio packets received and authenticated since joining.
    pub received_packets: u64,
    /// Loudest decoded sample (0.0 to 1.0) since the previous status: ~0 means the stream is silent.
    pub peak: f32,
    /// Name of the output device the audio is playing on (desktop), so a person can see where it goes.
    pub output_device: Option<String>,
    /// This app's slider and mute switch in the operating system's volume mixer (Windows only, else `None`). A muted
    /// or near-zero app plays at full scale into the sound card and is still silent, so the UI warns about it.
    pub app_volume: Option<f32>,
    pub app_muted: Option<bool>,
    pub max_late_ms: f64,
}
impl GuestStatus {
    fn new(phase: GuestPhase, message: impl Into<String>) -> Self {
        Self {
            phase, message: message.into(), rtt_us: None, fill_frames: None, drift_ppm: None, underruns: 0,
            late_packets: 0, lost_packets: 0, received_packets: 0, peak: 0.0, output_device: None, app_volume: None, app_muted: None, max_late_ms: 0.0,
        }
    }
}

#[derive(Clone, Copy)]
pub struct GuestOptions {
    /// Open the sound card and play. Disabled in tests, which only exercise pairing/sync.
    pub audio: bool,
}
impl Default for GuestOptions { fn default() -> Self { Self { audio: true } } }

pub struct Guest { rx: Receiver<GuestStatus>, stop: Stop }

impl Guest {
    /// Returns immediately; progress arrives through `poll`. `audio_port` 0 picks a free port.
    pub fn join(link: &str, audio_port: u16, delay_ms: u32, opts: GuestOptions) -> Guest {
        let (tx, rx) = channel();
        let stop = Stop::default();
        let (link, stop2) = (link.to_string(), stop.clone());
        thread::spawn(move || {
            // A panic in this thread would otherwise vanish silently and leave the UI waiting forever.
            let outcome = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| run(&link, audio_port, delay_ms, opts, &tx, &stop2)));
            let message = match outcome {
                Ok(Ok(())) => return,
                Ok(Err(e)) => friendly(&e),
                Err(p) => {
                    let text = p.downcast_ref::<&str>().map(|s| s.to_string()).or_else(|| p.downcast_ref::<String>().cloned()).unwrap_or_else(|| "unknown".into());
                    format!("Internal error: {text}")
                }
            };
            if !stop2.is_set() { let _ = tx.send(GuestStatus::new(GuestPhase::Error, message)); }
        });
        Guest { rx, stop }
    }
    pub fn poll(&self) -> Option<GuestStatus> { self.rx.try_recv().ok() }
    pub fn recv_timeout(&self, d: Duration) -> Option<GuestStatus> { self.rx.recv_timeout(d).ok() }
    /// Stops soon after; does not block (the worker may be inside a network wait).
    pub fn leave(&self) { self.stop.set(); }
}
impl Drop for Guest { fn drop(&mut self) { self.stop.set(); } }

fn friendly(e: &anyhow::Error) -> String {
    let m = e.to_string();
    if m.contains("fingerprint") { "This is not the device you scanned. Connection refused for your safety.".into() }
    else if m.contains("rejected") { "The host did not allow this device to join.".into() }
    else if m.contains("timed out") || m.contains("os error 10060") { "Could not reach the host. Are you on the same Wi-Fi?".into() }
    else { m }
}

#[derive(Default)]
struct SyncStats { rtt_us: AtomicI64, synced: AtomicU64, last_pong_ms: AtomicU64 }

/// Pings the host (fast at first, then every second) and feeds samples into the shared estimator.
fn spawn_sync_client(sock: UdpSocket, host: std::net::SocketAddr, start: Instant, key: Key, sync: Arc<Mutex<ClockSync>>, stats: Arc<SyncStats>, stop: Stop) {
    thread::spawn(move || {
        let _ = sock.set_read_timeout(Some(Duration::from_millis(200)));
        let (mut seq, mut buf) = (0u32, [0u8; 256]);
        while !stop.is_set() {
            let t0 = start.elapsed().as_micros() as u64;
            let ping = AudioPacket { seq, host_ts_us: 0, payload: t0.to_le_bytes().to_vec() };
            seq = seq.wrapping_add(1);
            if sock.send_to(&seal(&key, PING_ID, &ping), host).is_ok() {
                if let Ok((n, _)) = sock.recv_from(&mut buf) {
                    let t3 = start.elapsed().as_micros() as i64;
                    if let Some(p) = open(&key, PONG_ID, &buf[..n]) {
                        if p.payload.len() == 24 {
                            let g = |i: usize| u64::from_le_bytes(p.payload[i..i + 8].try_into().unwrap()) as i64;
                            if g(0) == t0 as i64 {
                                sync.lock().unwrap().add_sample(t0 as i64, g(8), g(16), t3);
                                stats.rtt_us.store((t3 - t0 as i64) - (g(16) - g(8)), Ordering::Relaxed);
                                stats.last_pong_ms.store(start.elapsed().as_millis() as u64, Ordering::Relaxed);
                                stats.synced.store(1, Ordering::Relaxed);
                            }
                        }
                    }
                }
            }
            thread::sleep(Duration::from_millis(if seq < 20 { 100 } else { 1000 }));
        }
    });
}

/// Opens the default output device and starts playing from `play`. Any stream error (device removed, route
/// changed) sets `broken` so the worker can reopen; the callback also stamps `beat` so a stream that silently
/// stops being serviced (some devices switch routes without reporting an error) is caught by the watchdog.
/// Returns the stream and the name of the device it opened on.
fn open_output(play: &Arc<Mutex<Playout>>, broken: &Arc<AtomicBool>, beat: &Arc<AtomicU64>, clock: Instant) -> Result<(cpal::Stream, String)> {
    let dev = cpal::default_host().default_output_device().ok_or_else(|| anyhow!("no audio output device"))?;
    let (cfg, device_rate) = output_config(&dev)?;
    play.lock().unwrap().set_output_rate(device_rate); // e.g. 44.1 kHz Bluetooth: the playout converts from 48 kHz
    let device_name = dev.name().unwrap_or_default();
    let ch = cfg.channels as usize;
    let p2 = play.clone();
    let flag = broken.clone();
    let hb = beat.clone();
    beat.store(clock.elapsed().as_millis() as u64, Ordering::Relaxed);
    let mut scratch: Vec<f32> = Vec::new();
    // Diagnostics: MPSP_AUDIO_TRACE=<file> logs every sound-card callback (time, frames asked for, queue fill,
    // underruns so far) to explain starvation/glitches offline.
    let mut atrace = std::env::var("MPSP_AUDIO_TRACE").ok().and_then(|path| std::fs::File::create(path).ok()).map(std::io::BufWriter::new);
    if let Some(t) = atrace.as_mut() { let _ = writeln!(t, "t_us,frames,fill_before,started,underruns_after"); }
    let mut rows = 0u32;
    // MPSP_AUDIO_DUMP=<file>: the stereo f32 samples actually delivered to the sound card (first ~30 s, raw little-endian).
    let mut adump = std::env::var("MPSP_AUDIO_DUMP").ok().and_then(|path| std::fs::File::create(path).ok());
    let mut dumped_frames = 0usize;
    let s = dev.build_output_stream(&cfg, move |data: &mut [f32], _| {
        hb.store(clock.elapsed().as_millis() as u64, Ordering::Relaxed); // watchdog: proves the stream is alive
        scratch.resize(data.len() / ch * 2, 0.0);
        {
            let mut p = p2.lock().unwrap();
            let (fill_before, started_before) = (p.queued_frames(), p.is_started());
            p.render(&mut scratch);
            if let Some(t) = atrace.as_mut() {
                let _ = writeln!(t, "{},{},{},{},{}", clock.elapsed().as_micros(), data.len() / ch, fill_before, started_before as u8, p.underruns);
                rows += 1;
                if rows % 100 == 0 { let _ = t.flush(); }
            }
        }
        if let Some(f) = adump.as_mut() {
            if dumped_frames < 30 * 48_000 {
                let bytes: Vec<u8> = scratch.iter().flat_map(|x| x.to_le_bytes()).collect();
                let _ = f.write_all(&bytes);
                dumped_frames += scratch.len() / 2;
            }
        }
        for (f, s) in data.chunks_mut(ch).zip(scratch.chunks(2)) {
            f[0] = s[0];
            if ch > 1 { f[1] = s[1]; for x in &mut f[2..] { *x = 0.0; } }
        }
    }, move |e| { eprintln!("playback error: {e}"); flag.store(true, Ordering::SeqCst); }, None)?;
    s.play()?;
    Ok((s, device_name))
}

fn run(link_str: &str, audio_port: u16, delay_ms: u32, opts: GuestOptions, tx: &Sender<GuestStatus>, stop: &Stop) -> Result<()> {
    let send = |s: GuestStatus| { let _ = tx.send(s); };
    platform_audio::init_com(); // needed on this thread to read the OS volume mixer (Windows)
    send(GuestStatus::new(GuestPhase::Pairing, "Connecting to the host..."));
    let link = link::parse(link_str)?;
    let addr = link.host_addr.to_socket_addrs()?.next().ok_or_else(|| anyhow!("cannot resolve host address"))?;
    let mut tcp = TcpStream::connect_timeout(&addr, Duration::from_secs(5))?;
    tcp.set_read_timeout(Some(Duration::from_secs(60)))?; // the host's operator must approve
    // Bind before pairing so the host is told the real audio port.
    let sock = UdpSocket::bind(("0.0.0.0", audio_port))?;
    let audio_port = sock.local_addr()?.port();
    send(GuestStatus::new(GuestPhase::AwaitingApproval, "Waiting for the host to approve this device..."));
    let name = std::env::var("COMPUTERNAME").or_else(|_| std::env::var("HOSTNAME")).unwrap_or_else(|_| "Guest device".into());
    let key = pairing::guest_pair(&mut tcp, &link.fingerprint, &link.token, &name, audio_port)?;
    drop(tcp);
    send(GuestStatus::new(GuestPhase::Pairing, "Synchronising clocks..."));

    let start = Instant::now();
    let sync = Arc::new(Mutex::new(ClockSync::default()));
    let stats = Arc::new(SyncStats::default());
    // Pings go from a separate socket so audio and control never share a receive queue.
    let ping_sock = UdpSocket::bind("0.0.0.0:0")?;
    spawn_sync_client(ping_sock, addr, start, key, sync.clone(), stats.clone(), stop.clone());

    let play = Arc::new(Mutex::new(Playout::new(PLAYOUT_TARGET)));
    // The cpal stream must stay alive in this thread for the whole session. It can die underneath us (Bluetooth
    // headphones connecting, headset unplugged, audio route change): the error callback raises `broken` and the
    // loop below reopens the output on whatever the default device is by then.
    let broken = Arc::new(AtomicBool::new(false));
    let beat = Arc::new(AtomicU64::new(0));
    let (mut stream, mut output_name) = if opts.audio {
        let (s, name) = open_output(&play, &broken, &beat, start)?;
        (Some(s), name)
    } else { (None, String::new()) };
    let mut reopen_at: Option<Instant> = None;
    let mut last_device_check = Instant::now();
    // While joining or right after the output was reopened, the receive loop was stalled (clock sync not yet settled,
    // or the OS opening a device), so packets that piled up arrive late in one burst. Playing them would leave the
    // queue ~100 ms over target for ~15 s. Packets that are late inside this window are dropped instead.
    let mut settle_until = Instant::now() + Duration::from_millis(1500);

    sock.set_read_timeout(Some(Duration::from_millis(2)))?;
    let mut dec = opus::Decoder::new(RATE, opus::Channels::Stereo)?;
    let mut jb = JitterBuffer::new(256);
    let (mut buf, mut pcm) = ([0u8; 2048], vec![0f32; FRAME * 2]);
    let mut last_status = Instant::now() - Duration::from_secs(1);
    let delay_us = delay_ms as i64 * 1000;
    let (mut late, mut lost, mut received, mut max_late_us) = (0u64, 0u64, 0u64, 0i64);
    let mut peak = 0f32;
    // Diagnostics: MPSP_TRACE=<file> writes one CSV row per packet (arrival, host timestamp, clock offset in use,
    // scheduled playout time, lateness) so jitter, timestamp bursts and clock-sync error can be told apart offline.
    let mut trace = std::env::var("MPSP_TRACE").ok().and_then(|path| std::fs::File::create(path).ok()).map(std::io::BufWriter::new);
    if let Some(t) = trace.as_mut() { let _ = writeln!(t, "arrival_us,seq,host_ts_us,offset_us,play_at_us,lateness_us"); }
    while !stop.is_set() {
        if opts.audio {
            let stalled = stream.is_some() && start.elapsed().as_millis() as u64 > beat.load(Ordering::Relaxed) + STREAM_STALL_MS;
            // Desktop only: a stream stays on the device it opened on, so Bluetooth connecting (Windows makes it the
            // new default) raises no error at all. Watch the default and follow it. Android reroutes by itself and
            // closes the stream, which the error/stall paths above already catch.
            let mut moved = false;
            #[cfg(not(target_os = "android"))]
            if stream.is_some() && last_device_check.elapsed() >= Duration::from_secs(1) {
                last_device_check = Instant::now();
                moved = output_device_changed(&output_name, default_output_name().as_deref());
            }
            #[cfg(target_os = "android")]
            let _ = &mut last_device_check;
            if stream.is_some() && (broken.swap(false, Ordering::SeqCst) || stalled || moved) {
                drop(stream.take());
                reopen_at = Some(Instant::now() + Duration::from_millis(500)); // let the OS finish switching routes
            }
            if stream.is_none() && reopen_at.is_some_and(|t| Instant::now() >= t) {
                match open_output(&play, &broken, &beat, start) {
                    Ok((s, name)) => {
                        play.lock().unwrap().reset();
                        jb = JitterBuffer::new(256); // anything queued for a past playout time is stale now
                        settle_until = Instant::now() + Duration::from_millis(800);
                        stream = Some(s);
                        output_name = name;
                        reopen_at = None;
                    }
                    Err(_) => reopen_at = Some(Instant::now() + Duration::from_secs(1)), // keep trying; the session stays up
                }
            }
        }
        if let Ok(n) = sock.recv(&mut buf) {
            if let Some(p) = open(&key, STREAM_ID, &buf[..n]) {
                received += 1;
                // play_at = host capture time on our clock + shared delay, minus what the playout queue already holds.
                // One short lock: an `if let` on `sync.lock()` would hold the guard for the whole body.
                let (mapped, offset) = { let c = sync.lock().unwrap(); (c.host_to_local(p.host_ts_us), c.offset_us().unwrap_or(0)) };
                if let Some(local) = mapped {
                    let play_at = local + delay_us - PLAYOUT_TARGET_US;
                    let arrival = start.elapsed().as_micros() as i64;
                    let lateness = arrival - play_at;
                    if lateness > 0 { late += 1; max_late_us = max_late_us.max(lateness); }
                    if let Some(t) = trace.as_mut() {
                        let _ = writeln!(t, "{arrival},{},{},{offset},{play_at},{lateness}", p.seq, p.host_ts_us);
                    }
                    if lateness > 0 && Instant::now() < settle_until {
                        // stall backlog: drop rather than play in a burst (a brief gap beats ~100 ms of extra delay)
                    } else {
                        jb.push(p.seq, play_at, p.payload);
                    }
                }
            }
        }
        loop {
            let now = start.elapsed().as_micros() as i64;
            let ok = match jb.pop(now) {
                Pop::Packet(d) => dec.decode_float(&d, &mut pcm, false).is_ok(),
                Pop::Lost => { lost += 1; dec.decode_float(&[], &mut pcm, false).is_ok() } // packet-loss concealment
                Pop::Empty => break,
            };
            if ok {
                peak = pcm.iter().fold(peak, |m, &x| m.max(x.abs()));
                play.lock().unwrap().push(&pcm);
            }
        }
        if last_status.elapsed() >= Duration::from_secs(1) {
            last_status = Instant::now();
            if let Some(t) = trace.as_mut() { let _ = t.flush(); }
            if stats.synced.load(Ordering::Relaxed) == 0 { continue; }
            let silent_for = start.elapsed().as_millis() as u64 - stats.last_pong_ms.load(Ordering::Relaxed);
            if Duration::from_millis(silent_for) > HOST_SILENCE_LIMIT {
                return Err(anyhow!("Lost connection to the host."));
            }
            let mixer = if opts.audio && stream.is_some() { platform_audio::own_session_volume() } else { None };
            let p = play.lock().unwrap();
            send(GuestStatus {
                phase: GuestPhase::Connected,
                message: if opts.audio && stream.is_none() { "Audio output changed, reconnecting...".into() } else { "Playing in sync".into() },
                rtt_us: Some(stats.rtt_us.load(Ordering::Relaxed)),
                fill_frames: Some(p.fill),
                drift_ppm: Some((p.ratio - 1.0) * 1e6),
                underruns: p.underruns,
                late_packets: late,
                lost_packets: lost,
                received_packets: received,
                peak,
                output_device: if output_name.is_empty() { None } else { Some(output_name.clone()) },
                app_volume: mixer.map(|m| m.volume),
                app_muted: mixer.map(|m| m.muted),
                max_late_ms: max_late_us as f64 / 1000.0,
            });
            max_late_us = 0;
            peak = 0.0;
        }
    }
    if let Some(t) = trace.as_mut() { let _ = t.flush(); }
    Ok(())
}
