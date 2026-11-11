//! Host and guest in one process (no sound card): pairing, approval, sync, kick, denial, impostor links.
use mpsp_engine::*;
use std::time::{Duration, Instant};

fn tmp(name: &str) -> std::path::PathBuf {
    let d = std::env::temp_dir().join(format!("mpsp-test-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&d);
    d
}

fn start_host(name: &str) -> Host {
    Host::start("127.0.0.1", 0, &tmp(name), HostOptions { source: AudioSource::None }).unwrap()
}

fn wait_host<T>(h: &Host, secs: u64, mut f: impl FnMut(HostEvent) -> Option<T>) -> T {
    let end = Instant::now() + Duration::from_secs(secs);
    while Instant::now() < end {
        if let Some(e) = h.recv_timeout(Duration::from_millis(100)) { if let Some(v) = f(e) { return v; } }
    }
    panic!("timed out waiting for host event");
}

fn wait_guest<T>(g: &Guest, secs: u64, mut f: impl FnMut(&GuestStatus) -> Option<T>) -> T {
    let end = Instant::now() + Duration::from_secs(secs);
    while Instant::now() < end {
        if let Some(s) = g.recv_timeout(Duration::from_millis(100)) { if let Some(v) = f(&s) { return v; } }
    }
    panic!("timed out waiting for guest status");
}

fn link(h: &Host) -> String {
    wait_host(h, 5, |e| match e { HostEvent::PairingLink { link } => Some(link), _ => None })
}

fn latest_link(h: &Host) -> String {
    // After an attempt the host issues a new link; take the last one currently queued, else wait for one.
    let mut last = None;
    while let Some(e) = h.recv_timeout(Duration::from_millis(300)) { if let HostEvent::PairingLink { link } = e { last = Some(link); } }
    last.unwrap_or_else(|| link(h))
}

fn approve_next(h: &Host, allow: bool) -> String {
    let (id, name) = wait_host(h, 10, |e| match e { HostEvent::JoinRequest { id, name, .. } => Some((id, name)), _ => None });
    h.respond(&id, allow);
    name
}

#[test]
fn pair_approve_sync_then_kick() {
    let host = start_host("a");
    let guest = Guest::join(&link(&host), 0, 80, GuestOptions { audio: false });
    approve_next(&host, true);
    let gid = wait_host(&host, 10, |e| match e { HostEvent::Guests { guests } if guests.len() == 1 => Some(guests[0].id.clone()), _ => None });
    let rtt = wait_guest(&guest, 10, |s| (s.phase == GuestPhase::Connected).then_some(s.rtt_us));
    assert!(rtt.is_some_and(|r| (0..50_000).contains(&r)), "rtt {rtt:?}");

    host.kick(&gid);
    wait_host(&host, 5, |e| matches!(e, HostEvent::Guests { guests } if guests.is_empty()).then_some(()));
    // A kicked guest stops getting pongs and must notice (within the 5 s silence limit plus polling slack).
    let msg = wait_guest(&guest, 15, |s| (s.phase == GuestPhase::Error).then(|| s.message.clone()));
    assert!(msg.contains("Lost connection"), "{msg}");
}

#[test]
fn denied_guest_is_told_no_and_host_stays_empty() {
    let host = start_host("b");
    let guest = Guest::join(&link(&host), 0, 80, GuestOptions { audio: false });
    approve_next(&host, false);
    let msg = wait_guest(&guest, 10, |s| (s.phase == GuestPhase::Error).then(|| s.message.clone()));
    assert!(msg.contains("did not allow"), "{msg}");
    assert!(host.poll().into_iter().all(|e| !matches!(e, HostEvent::Guests { ref guests } if !guests.is_empty())));
}

#[test]
fn two_guests_and_each_pairing_link_is_single_use() {
    let host = start_host("c");
    let first = link(&host);
    let g1 = Guest::join(&first, 0, 80, GuestOptions { audio: false });
    approve_next(&host, true);
    wait_guest(&g1, 10, |s| (s.phase == GuestPhase::Connected).then_some(()));

    // Reusing the already-consumed link must fail (host rejects the old token).
    let replay = Guest::join(&first, 0, 80, GuestOptions { audio: false });
    wait_guest(&replay, 10, |s| (s.phase == GuestPhase::Error).then_some(()));

    let g2 = Guest::join(&latest_link(&host), 0, 80, GuestOptions { audio: false });
    approve_next(&host, true);
    wait_guest(&g2, 10, |s| (s.phase == GuestPhase::Connected).then_some(()));
    let n = wait_host(&host, 5, |e| match e { HostEvent::Guests { guests } if guests.len() == 2 => Some(guests.len()), _ => None });
    assert_eq!(n, 2);
}

#[test]
fn link_with_wrong_fingerprint_is_refused_before_any_token_is_sent() {
    let host = start_host("d");
    let good = link(&host);
    let bad = good.replace("&fp=", "&fp=00"); // shifts the fingerprint: 33 bytes -> rejected at parse
    let g = Guest::join(&bad, 0, 80, GuestOptions { audio: false });
    wait_guest(&g, 5, |s| (s.phase == GuestPhase::Error).then_some(()));
    // A well-formed but wrong fingerprint (another host's identity) must be refused by the handshake itself.
    let other = start_host("e");
    let fp_other = link(&other).split("&fp=").nth(1).unwrap().split('&').next().unwrap().to_string();
    let fp_host = good.split("&fp=").nth(1).unwrap().split('&').next().unwrap().to_string();
    let impostor = good.replace(&fp_host, &fp_other);
    let g2 = Guest::join(&impostor, 0, 80, GuestOptions { audio: false });
    let msg = wait_guest(&g2, 10, |s| (s.phase == GuestPhase::Error).then(|| s.message.clone()));
    assert!(msg.contains("not the device you scanned"), "{msg}");
}

#[test]
fn events_serialize_as_tagged_json() {
    let e = HostEvent::JoinRequest { id: "g1".into(), name: "Pixel".into(), address: "1.2.3.4".into() };
    let j = serde_json::to_string(&e).unwrap();
    assert_eq!(j, r#"{"type":"join_request","id":"g1","name":"Pixel","address":"1.2.3.4"}"#);
}

/// The Android path: the platform pushes 16-bit PCM into the host instead of the host reading a sound card.
#[test]
fn pushed_pcm_reaches_a_paired_guest() {
    let host = Host::start("127.0.0.1", 0, &tmp("ext"), HostOptions { source: AudioSource::External }).unwrap();
    let src = host.external_source().expect("External hosts expose a source");
    assert!(Host::start("127.0.0.1", 0, &tmp("ext-none"), HostOptions { source: AudioSource::None }).unwrap().external_source().is_none());
    let guest = Guest::join(&link(&host), 0, 160, GuestOptions { audio: false });
    approve_next(&host, true);
    wait_guest(&guest, 10, |s| (s.phase == GuestPhase::Connected).then_some(()));

    // 3 s of a 440 Hz tone in 10 ms chunks at real-time pace, like the capture thread does.
    let pusher = std::thread::spawn(move || {
        for k in 0..300usize {
            let chunk: Vec<i16> = (0..480usize).flat_map(|i| {
                let v = ((2.0 * std::f32::consts::PI * 440.0 * (k * 480 + i) as f32 / 48_000.0).sin() * 8000.0) as i16;
                [v, v]
            }).collect();
            src.push_i16(&chunk);
            std::thread::sleep(Duration::from_millis(10));
        }
    });
    let received = wait_guest(&guest, 10, |s| (s.received_packets >= 100).then_some(s.received_packets));
    assert!(received >= 100, "guest authenticated {received} audio packets");
    // The tone was pushed at amplitude 8000/32768 = 0.24: it must come out of the decoder as a clearly audible signal.
    let peak = wait_guest(&guest, 5, |s| (s.peak > 0.05).then_some(s.peak));
    assert!((0.15..0.35).contains(&peak), "decoded peak {peak} should be near 0.24");
    pusher.join().unwrap();
}

#[test]
fn pushing_before_any_guest_pairs_is_harmless() {
    let host = Host::start("127.0.0.1", 0, &tmp("ext-empty"), HostOptions { source: AudioSource::External }).unwrap();
    let src = host.external_source().unwrap();
    src.push_i16(&vec![1000i16; 960 * 5]); // no guests: frames are dropped, nothing panics
    src.push_i16(&[]);                      // empty push is fine
    src.push_i16(&[7i16; 3]);               // odd, partial chunk is buffered, not an error
}
