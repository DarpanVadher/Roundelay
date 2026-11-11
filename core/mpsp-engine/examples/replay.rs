//! Replays a raw 16-bit stereo 48 kHz file through the real host (External source) -> network -> real guest
//! (with sound card output) path on this machine. Tests the guest's playback independent of any phone.
//!   cargo run --release -p mpsp-engine --example replay -- capture.raw [delay_ms] [loops]
use mpsp_engine::*;
use std::time::{Duration, Instant};

fn main() {
    let path = std::env::args().nth(1).expect("raw file path");
    let delay: u32 = std::env::args().nth(2).and_then(|s| s.parse().ok()).unwrap_or(160);
    let loops: usize = std::env::args().nth(3).and_then(|s| s.parse().ok()).unwrap_or(1);
    let bytes = std::fs::read(&path).expect("read file");
    let one: Vec<i16> = bytes.chunks_exact(2).map(|b| i16::from_le_bytes([b[0], b[1]])).collect();
    let pcm: Vec<i16> = one.iter().copied().cycle().take(one.len() * loops).collect();
    let dir = std::env::temp_dir().join("mpsp-replay");
    let host = Host::start("127.0.0.1", 0, &dir, HostOptions { source: AudioSource::External }).expect("host");
    let src = host.external_source().unwrap();
    let link = loop { if let Some(HostEvent::PairingLink { link }) = host.recv_timeout(Duration::from_secs(5)) { break link; } };
    let guest = Guest::join(&link, 0, delay, GuestOptions { audio: true });
    let t0 = Instant::now();
    let mut pos = 0usize;
    let mut next = Instant::now();
    let mut last_print = Instant::now();
    let mut joined = false;
    while pos < pcm.len() || t0.elapsed() < Duration::from_secs(3) {
        while let Some(e) = host.poll() { if let HostEvent::JoinRequest { id, .. } = e { host.respond(&id, true); } }
        while let Some(s) = guest.poll() {
            if s.phase == GuestPhase::Error { println!("guest error: {}", s.message); return; }
            if s.phase == GuestPhase::Connected {
                joined = true;
                if last_print.elapsed() >= Duration::from_secs(2) {
                    last_print = Instant::now();
                    println!("guest: received={} late={} lost={} underruns={} buffer={} frames level={:.0}% output={} mixer(volume={:?} muted={:?})",
                        s.received_packets, s.late_packets, s.lost_packets, s.underruns, s.fill_frames.unwrap_or(0), s.peak * 100.0,
                        s.output_device.as_deref().unwrap_or("-"), s.app_volume, s.app_muted);
                }
            }
        }
        // Catch up on every chunk that is due. Windows sleeps ~15 ms at a time, so pushing one chunk per pass would
        // feed audio at only ~64% of real time and starve the guest (an earlier version of this tool did exactly that).
        if !joined { next = Instant::now(); }
        while joined && pos < pcm.len() && Instant::now() >= next {
            let end = (pos + 960).min(pcm.len()); // 10 ms of interleaved stereo
            src.push_i16(&pcm[pos..end]);
            pos = end;
            next += Duration::from_millis(10);
        }
        std::thread::sleep(Duration::from_millis(1));
    }
    std::thread::sleep(Duration::from_secs(2));
    println!("replayed {} s", pcm.len() / 2 / 48000);
}
