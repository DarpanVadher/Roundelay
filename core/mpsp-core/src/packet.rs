//! Audio packet wire format with AEAD encryption.
//! Layout: [seq u32 LE][host_ts_us u64 LE][ciphertext+tag]. Header is authenticated (AAD);
//! nonce = 4 zero bytes + seq(4) + 4 bytes of stream id, so each (key, seq) is unique.
use chacha20poly1305::{aead::{Aead, KeyInit, Payload}, ChaCha20Poly1305, Nonce};

pub const HEADER_LEN: usize = 12;

#[derive(Debug, PartialEq)]
pub struct AudioPacket { pub seq: u32, pub host_ts_us: u64, pub payload: Vec<u8> }

fn nonce(seq: u32, stream_id: u32) -> Nonce {
    let mut n = [0u8; 12];
    n[4..8].copy_from_slice(&seq.to_le_bytes());
    n[8..12].copy_from_slice(&stream_id.to_le_bytes());
    *Nonce::from_slice(&n)
}

pub fn seal(key: &[u8; 32], stream_id: u32, p: &AudioPacket) -> Vec<u8> {
    let mut out = Vec::with_capacity(HEADER_LEN + p.payload.len() + 16);
    out.extend_from_slice(&p.seq.to_le_bytes());
    out.extend_from_slice(&p.host_ts_us.to_le_bytes());
    let ct = ChaCha20Poly1305::new(key.into())
        .encrypt(&nonce(p.seq, stream_id), Payload { msg: &p.payload, aad: &out[..HEADER_LEN] })
        .expect("encrypt");
    out.extend_from_slice(&ct);
    out
}

pub fn open(key: &[u8; 32], stream_id: u32, data: &[u8]) -> Option<AudioPacket> {
    if data.len() < HEADER_LEN + 16 { return None; }
    let seq = u32::from_le_bytes(data[0..4].try_into().ok()?);
    let host_ts_us = u64::from_le_bytes(data[4..12].try_into().ok()?);
    let payload = ChaCha20Poly1305::new(key.into())
        .decrypt(&nonce(seq, stream_id), Payload { msg: &data[HEADER_LEN..], aad: &data[..HEADER_LEN] })
        .ok()?;
    Some(AudioPacket { seq, host_ts_us, payload })
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn roundtrip_and_tamper() {
        let key = [7u8; 32];
        let p = AudioPacket { seq: 5, host_ts_us: 123456, payload: vec![1, 2, 3, 4] };
        let mut w = seal(&key, 9, &p);
        assert_eq!(open(&key, 9, &w), Some(p));
        assert!(open(&[8u8; 32], 9, &w).is_none());
        w[2] ^= 1; // tampered header
        assert!(open(&key, 9, &w).is_none());
    }
}
