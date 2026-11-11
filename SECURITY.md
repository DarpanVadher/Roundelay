# Security policy

## Status

Roundelay is early-stage software. Its pairing and encryption design (Noise XX handshake, per-guest ChaCha20-Poly1305
keys, identity pinned by a QR fingerprint, host approval for every device) has **not been independently reviewed**.
There are no supported release versions yet; fixes go to the `main` branch.

## Reporting a vulnerability

Please **do not open a public issue** for a security problem. Report it privately:

1. Use the repository's **"Report a vulnerability"** button on the Security tab (GitHub private security advisories).
2. Include what you found, how to reproduce it, and what an attacker could do with it.

You should get an acknowledgement within a few days. Please give us reasonable time to fix the problem before
discussing it publicly, and we will credit you in the fix if you want.

> Maintainers: before publishing, confirm private vulnerability reporting is enabled for the repository and add a
> backup contact address here if you have one.

## What is in scope

- The pairing handshake, token and fingerprint handling, and host approval.
- Packet encryption, nonce handling and replay behavior.
- Anything that lets a device on the network join or listen without the host's approval.
- Memory-safety bugs in the engine or its C/JNI interface.

## Known limitations (not secrets, already documented)

- The host's long-term identity key is stored in a plain file in its data folder.
- Paired devices are not persisted; every join uses a fresh single-use token.
- There is no protection against someone who can already run code on the host or guest device.
- The protocol has not been audited.
