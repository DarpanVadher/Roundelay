# Changelog

All notable changes to Roundelay are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow
[Semantic Versioning](https://semver.org/). While the major version is 0, minor releases may change behavior.

The section for a version is used as that version's GitHub Release notes, so write it for users.

## [Unreleased]

## [0.2.0] - 2026-11-12

### Added
- **Wi-Fi in the QR.** A host can switch on "Include hotspot Wi-Fi in the QR" so guests scan once to join the hotspot and
  pair. Type the hotspot's name and password (saved on that device only), or on Android tap "Create a hotspot for me" to
  have the app start its own hotspot. The Wi-Fi password is readable by anyone who sees the QR, so it is off by default.
- Android guests join the hotspot from the QR through Android's own prompt (Android 10 or newer). Windows guests are shown
  the name and password to copy.
- **Privacy & legal** pages inside the app and on the website: privacy policy, terms, GDPR, cookies, data handling,
  third-party disclosure, security, breach procedure, intellectual property, open-source licences and payments.
- New look: cobalt and sun colours with light and dark themes, glass cards, an animated Roundelay mark and a drifting audio
  background. Everything stops moving when the system asks for reduced motion.
- New app icon on Android (adaptive, with a themed monochrome layer), Windows, iOS, macOS and the website.

### Changed
- Screens now scroll with the mouse wheel and scrollbar anywhere in the window on desktop, not only over the centre column.

### Known limitations
- Creating a hotspot from the app starts a separate temporary hotspot (it cannot read your phone's normal hotspot password);
  guests have no internet through it.
- Joining a hotspot from the QR has only been tried on one Android phone so far.
- iOS is not available yet. Linux and macOS builds are experimental guests; host capture is Windows and Android only.
- Downloads are not code-signed, so Windows SmartScreen and macOS Gatekeeper will warn on first run.

## [0.1.0] - 2026-11-11

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

[Unreleased]: https://github.com/DarpanVadher/Roundelay/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/DarpanVadher/Roundelay/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/DarpanVadher/Roundelay/releases/tag/v0.1.0
