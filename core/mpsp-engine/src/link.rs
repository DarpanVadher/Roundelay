use anyhow::{anyhow, Result};
use mpsp_core::pairing::{self, TOKEN_LEN};

pub struct PairingLink { pub host_addr: String, pub fingerprint: Vec<u8>, pub token: [u8; TOKEN_LEN] }

pub fn build(lan_ip: &str, port: u16, host_pubkey: &[u8], token: &[u8; TOKEN_LEN]) -> String {
    format!("mpsp://pair?h={lan_ip}:{port}&fp={}&t={}", pairing::to_hex(&pairing::fingerprint(host_pubkey)), pairing::to_hex(token))
}

pub fn parse(uri: &str) -> Result<PairingLink> {
    let q = uri.trim().strip_prefix("mpsp://pair?").ok_or_else(|| anyhow!("not an mpsp pairing link"))?;
    let get = |k: &str| q.split('&').find_map(|kv| kv.strip_prefix(&format!("{k}="))).ok_or_else(|| anyhow!("pairing link is missing '{k}'"));
    let fingerprint = pairing::from_hex(get("fp")?)?;
    if fingerprint.len() != 32 { return Err(anyhow!("bad fingerprint length")); }
    Ok(PairingLink {
        host_addr: get("h")?.to_string(),
        fingerprint,
        token: pairing::from_hex(get("t")?)?.try_into().map_err(|_| anyhow!("bad token length"))?,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn build_parse_roundtrip_and_rejects_garbage() {
        let tok = [9u8; TOKEN_LEN];
        let uri = build("10.0.0.5", 5005, b"pubkey", &tok);
        let p = parse(&uri).unwrap();
        assert_eq!((p.host_addr.as_str(), p.token), ("10.0.0.5:5005", tok));
        assert_eq!(p.fingerprint, pairing::fingerprint(b"pubkey"));
        assert!(parse("http://x").is_err());
        assert!(parse("mpsp://pair?h=1.2.3.4:1&fp=zz&t=00").is_err());
        assert!(parse(&uri.replace("&t=", "&x=")).is_err());
    }
}
