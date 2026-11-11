//! Secure pairing over any Read+Write stream (TCP in practice).
//!
//! QR payload = host address + SHA-256 fingerprint of the host's static public key + one-time token.
//! Noise_XX handshake: the guest checks the host's static key against the QR fingerprint BEFORE
//! revealing the token (so an impostor never sees it); the host checks the token, then asks the
//! operator to approve; only then does it send a fresh random per-guest session key, inside the
//! encrypted Noise transport channel.
use anyhow::{anyhow, bail, Result};
use rand::{rngs::OsRng, RngCore};
use sha2::{Digest, Sha256};
use std::io::{Read, Write};

const PATTERN: &str = "Noise_XX_25519_ChaChaPoly_SHA256";
pub const TOKEN_LEN: usize = 16;

pub struct GuestInfo { pub name: String, pub audio_port: u16 }

pub fn fingerprint(pubkey: &[u8]) -> [u8; 32] { Sha256::digest(pubkey).into() }
pub fn random_bytes<const N: usize>() -> [u8; N] { let mut b = [0u8; N]; OsRng.fill_bytes(&mut b); b }
pub fn generate_static_key() -> Result<snow::Keypair> { Ok(snow::Builder::new(PATTERN.parse()?).generate_keypair()?) }

pub fn to_hex(b: &[u8]) -> String { b.iter().map(|x| format!("{x:02x}")).collect() }
pub fn from_hex(s: &str) -> Result<Vec<u8>> {
    if s.len() % 2 != 0 { bail!("bad hex"); }
    (0..s.len()).step_by(2).map(|i| u8::from_str_radix(&s[i..i + 2], 16).map_err(|e| anyhow!(e))).collect()
}

fn write_frame(w: &mut impl Write, d: &[u8]) -> Result<()> {
    w.write_all(&(d.len() as u16).to_be_bytes())?; w.write_all(d)?; w.flush()?; Ok(())
}
fn read_frame(r: &mut impl Read) -> Result<Vec<u8>> {
    let mut l = [0u8; 2]; r.read_exact(&mut l)?;
    let mut b = vec![0u8; u16::from_be_bytes(l) as usize]; r.read_exact(&mut b)?; Ok(b)
}

/// Host side. Returns the new session key and the guest that was approved.
pub fn host_pair<S: Read + Write>(
    s: &mut S, static_private: &[u8], token: &[u8; TOKEN_LEN], approve: impl FnOnce(&GuestInfo) -> bool,
) -> Result<([u8; 32], GuestInfo)> {
    let mut hs = snow::Builder::new(PATTERN.parse()?).local_private_key(static_private).build_responder()?;
    let mut buf = vec![0u8; 2048];
    hs.read_message(&read_frame(s)?, &mut buf)?;
    let n = hs.write_message(&[], &mut buf)?; write_frame(s, &buf[..n])?;
    let n = hs.read_message(&read_frame(s)?, &mut buf)?;
    let p = buf[..n].to_vec();
    if p.len() < TOKEN_LEN + 2 { bail!("short pairing payload"); }
    let token_ok = p[..TOKEN_LEN].iter().zip(token).fold(0u8, |a, (x, y)| a | (x ^ y)) == 0; // constant time
    let name: String = String::from_utf8_lossy(&p[TOKEN_LEN + 2..]).chars().filter(|c| !c.is_control()).take(32).collect();
    let guest = GuestInfo { audio_port: u16::from_be_bytes([p[TOKEN_LEN], p[TOKEN_LEN + 1]]), name };
    let mut ts = hs.into_transport_mode()?;
    if !token_ok || !approve(&guest) {
        let n = ts.write_message(&[0], &mut buf)?; write_frame(s, &buf[..n])?;
        bail!(if token_ok { "guest not approved" } else { "invalid pairing token" });
    }
    let key: [u8; 32] = random_bytes();
    let mut reply = vec![1u8]; reply.extend_from_slice(&key);
    let n = ts.write_message(&reply, &mut buf)?; write_frame(s, &buf[..n])?;
    Ok((key, guest))
}

/// Guest side. Fails (without sending the token) if the host's key doesn't match the QR fingerprint.
pub fn guest_pair<S: Read + Write>(
    s: &mut S, expected_fp: &[u8], token: &[u8; TOKEN_LEN], name: &str, audio_port: u16,
) -> Result<[u8; 32]> {
    let kp = generate_static_key()?;
    let mut hs = snow::Builder::new(PATTERN.parse()?).local_private_key(&kp.private).build_initiator()?;
    let mut buf = vec![0u8; 2048];
    let n = hs.write_message(&[], &mut buf)?; write_frame(s, &buf[..n])?;
    hs.read_message(&read_frame(s)?, &mut buf)?;
    let rs = hs.get_remote_static().ok_or_else(|| anyhow!("no host key"))?;
    if fingerprint(rs) != expected_fp { bail!("host fingerprint mismatch - possible impostor, aborting"); }
    let mut payload = token.to_vec();
    payload.extend_from_slice(&audio_port.to_be_bytes());
    payload.extend_from_slice(name.as_bytes());
    let n = hs.write_message(&payload, &mut buf)?; write_frame(s, &buf[..n])?;
    let mut ts = hs.into_transport_mode()?;
    let n = ts.read_message(&read_frame(s)?, &mut buf)?;
    if n != 33 || buf[0] != 1 { bail!("pairing rejected by host"); }
    Ok(buf[1..33].try_into()?)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::{TcpListener, TcpStream};

    /// Runs a host on loopback; returns (addr, host static public key, join handle yielding the host result).
    fn spawn_host(token: [u8; 16], approve: bool) -> (std::net::SocketAddr, Vec<u8>, std::thread::JoinHandle<Result<([u8; 32], GuestInfo)>>) {
        let kp = generate_static_key().unwrap();
        let l = TcpListener::bind("127.0.0.1:0").unwrap();
        let addr = l.local_addr().unwrap();
        let (private, public) = (kp.private.clone(), kp.public.clone());
        let h = std::thread::spawn(move || { let (mut s, _) = l.accept()?; host_pair(&mut s, &private, &token, |_| approve) });
        (addr, public, h)
    }

    #[test]
    fn pairs_and_shares_key() {
        let token = random_bytes();
        let (addr, public, h) = spawn_host(token, true);
        let mut s = TcpStream::connect(addr).unwrap();
        let gk = guest_pair(&mut s, &fingerprint(&public), &token, "Phone", 5004).unwrap();
        let (hk, g) = h.join().unwrap().unwrap();
        assert_eq!(gk, hk);
        assert_eq!((g.name.as_str(), g.audio_port), ("Phone", 5004));
    }

    #[test]
    fn wrong_token_rejected() {
        let (addr, public, h) = spawn_host(random_bytes(), true);
        let mut s = TcpStream::connect(addr).unwrap();
        assert!(guest_pair(&mut s, &fingerprint(&public), &random_bytes(), "x", 1).is_err());
        assert!(h.join().unwrap().is_err());
    }

    #[test]
    fn impostor_host_rejected_before_token_sent() {
        let token = random_bytes();
        let (addr, _public, h) = spawn_host(token, true);
        let mut s = TcpStream::connect(addr).unwrap();
        let err = guest_pair(&mut s, &fingerprint(b"some other host key"), &token, "x", 1).unwrap_err();
        assert!(err.to_string().contains("fingerprint"));
        drop(s);
        assert!(h.join().unwrap().is_err()); // host never got the token message
    }

    #[test]
    fn unapproved_guest_gets_no_key() {
        let token = random_bytes();
        let (addr, public, h) = spawn_host(token, false);
        let mut s = TcpStream::connect(addr).unwrap();
        assert!(guest_pair(&mut s, &fingerprint(&public), &token, "x", 1).is_err());
        assert!(h.join().unwrap().is_err());
    }
}
