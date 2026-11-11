# Changelog

All notable changes to Roundelay are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow
[Semantic Versioning](https://semver.org/). While the major version is 0, minor releases may change behavior.

The section for a version is used as that version's GitHub Release notes, so write it for users.

## [Unreleased]

## [0.1.0] - TBD

First public release.

### Added
- Share the audio a Windows PC or Android phone is playing with other devices on the same Wi-Fi or hotspot,
  played in sync on every guest.
- Pair by scanning a QR code; the host approves each device. Audio is encrypted end to end.
- Clock synchronisation and drift correction between host and guests, with an adjustable latency.
- Follows your Bluetooth headphones and speakers when you switch the output device on Windows.
- Warns when the Windows volume mixer has muted the app.
- Android host (captures other apps' audio) and Android guest.

### Known limitations
- iOS is not available yet. Linux and macOS builds are experimental guests; host capture is Windows and Android only.
- Downloads are not code-signed, so Windows SmartScreen and macOS Gatekeeper will warn on first run.

[Unreleased]: https://github.com/DarpanVadher/Roundelay/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/DarpanVadher/Roundelay/releases/tag/v0.1.0
