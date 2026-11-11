//! Loopback diagnostic: real host capture + real encode/network/decode path, guest without a sound card
//! (so no feedback loop). Play any audio on this machine while it runs.
//!   MPSP_TRACE=trace.csv cargo run --release -p mpsp-engine --example diag -- <seconds> [delay_ms]
use mpsp_engine::*;
use std::time::{Duration, Instant};

fn main() {
    let secs: u64 = std::env::args().nth(1).and_then(|s| s.parse().ok()).unwrap_or(30);
    let delay: u32 = std::env::args().nth(2).and_then(|s| s.parse().ok()).unwrap_or(80);
    let dir = std::env::temp_dir().join("mpsp-diag");
    let host = Host::start("127.0.0.1", 0, &dir, HostOptions { source: if std::env::var("DIAG_NOAUDIO").is_err() { AudioSource::SystemLoopback } else { AudioSource::None } }).expect("host");
    let link = loop { if let Some(HostEvent::PairingLink { link }) = host.recv_timeout(Duration::from_secs(5)) { break link; } };
    let guest = Guest::join(&link, 0, delay, GuestOptions { audio: false });
    let end = Instant::now() + Duration::from_secs(secs);
    let mut last = None;
    while Instant::now() < end {
        if let Some(HostEvent::JoinRequest { id, .. }) = host.recv_timeout(Duration::from_millis(50)) { println!("host approves {id}"); host.respond(&id, true); }
        while let Some(s) = guest.poll() {
            println!("[{:>5.1}s] guest {:?}: {}", (Instant::now() - (end - Duration::from_secs(secs))).as_secs_f32(), s.phase, s.message);
            last = Some(s);
        }
    }
    guest.leave();
    std::thread::sleep(Duration::from_millis(500)); // let the guest thread flush its trace
    if let Some(s) = last { println!("final: {:?} rtt={:?}us late={} lost={}", s.phase, s.rtt_us, s.late_packets, s.lost_packets); }
}
