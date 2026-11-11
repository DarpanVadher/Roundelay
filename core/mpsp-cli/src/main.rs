//! Terminal front-end over `mpsp-engine` (same engine the Flutter app uses).
//!   mpsp-cli host <lan_ip> [port]               show a pairing QR, approve guests, stream system audio
//!   mpsp-cli guest <mpsp://pair?...> [audio_port] [delay_ms]
use anyhow::{anyhow, Result};
use mpsp_engine::{Guest, GuestOptions, GuestPhase, Host, HostEvent, HostOptions};
use std::io::Write;
use std::sync::mpsc;
use std::time::Duration;

fn host(lan_ip: &str, port: u16) -> Result<()> {
    let h = Host::start(lan_ip, port, std::path::Path::new("."), HostOptions::default())?;
    println!("Sharing this device's audio. Pairing port {}. Ctrl+C to stop.", h.port());
    // stdin is read on its own thread so a pending approval prompt never blocks event handling
    let (line_tx, line_rx) = mpsc::channel::<String>();
    std::thread::spawn(move || loop {
        let mut l = String::new();
        if std::io::stdin().read_line(&mut l).unwrap_or(0) == 0 { break; }
        let _ = line_tx.send(l);
    });
    let mut pending: Option<String> = None;
    loop {
        if let Some(id) = pending.clone() {
            if let Ok(l) = line_rx.try_recv() {
                h.respond(&id, l.trim().eq_ignore_ascii_case("y"));
                pending = None;
            }
        }
        match h.recv_timeout(Duration::from_millis(100)) {
            Some(HostEvent::PairingLink { link }) => {
                let qr = qrcode::QrCode::new(link.as_bytes())?.render::<qrcode::render::unicode::Dense1x2>().build();
                println!("\nScan this QR to add a guest (or paste the link):\n{qr}\n{link}");
            }
            Some(HostEvent::JoinRequest { id, name, address }) => {
                print!("Allow \"{name}\" ({address}) to join? [y/N] ");
                let _ = std::io::stdout().flush();
                pending = Some(id);
            }
            Some(HostEvent::Guests { guests }) => println!("Connected: {}", guests.iter().map(|g| g.name.as_str()).collect::<Vec<_>>().join(", ")),
            Some(HostEvent::Error { message }) => return Err(anyhow!(message)),
            None => {}
        }
    }
}

fn guest(link: &str, port: u16, delay_ms: u32) -> Result<()> {
    let g = Guest::join(link, port, delay_ms, GuestOptions::default());
    loop {
        if let Some(s) = g.recv_timeout(Duration::from_millis(200)) {
            match s.phase {
                GuestPhase::Error => return Err(anyhow!(s.message)),
                GuestPhase::Connected => println!(
                    "{} | rtt {:.1} ms | buffer {} frames | drift {:+.0} ppm | underruns {} | received {} late {} lost {} | level {:.0}%",
                    s.message, s.rtt_us.unwrap_or(0) as f64 / 1000.0, s.fill_frames.unwrap_or(0), s.drift_ppm.unwrap_or(0.0), s.underruns,
                    s.received_packets, s.late_packets, s.lost_packets, s.peak * 100.0),
                _ => println!("{}", s.message),
            }
        }
    }
}

fn main() -> Result<()> {
    let a: Vec<String> = std::env::args().collect();
    match a.get(1).map(String::as_str) {
        Some("host") if a.len() > 2 => host(&a[2], a.get(3).and_then(|p| p.parse().ok()).unwrap_or(5005)),
        Some("guest") if a.len() > 2 => guest(&a[2], a.get(3).and_then(|p| p.parse().ok()).unwrap_or(5004), a.get(4).and_then(|s| s.parse().ok()).unwrap_or(80)),
        _ => Err(anyhow!("usage: mpsp-cli host <lan_ip> [port] | guest <link> [audio_port] [delay_ms]")),
    }
}
