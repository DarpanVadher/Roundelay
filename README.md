# Roundelay

Play one device's audio on every device nearby, in sync. Over your own network, with no accounts and no internet.

One device is the **host**: it shares whatever it is playing. Any number of **guests** join by scanning a QR code,
the host approves each one, and everyone plays the same audio at the same moment.

> **Status: early and experimental.** It works end to end on the hardware it was developed on (see
> [Tested on](#tested-on)), but it is young, the pairing protocol has **not been independently audited**, and
> several platforms are not built yet. Please read [Known limitations](#known-limitations) before relying on it.

## Download

Get the latest build for Windows, Android, Linux or macOS from the
[Releases page](https://github.com/DarpanVadher/Roundelay/releases/latest) or the
[project website](https://darpanvadher.github.io/Roundelay/). Windows and Android are supported; Linux and macOS are
experimental guests; iOS is not available yet. Maintainers: see [docs/RELEASING.md](docs/RELEASING.md).

## What it does

- **Host shares system audio.** On Windows, whatever the PC plays. On Android, whatever other apps play (apps can
  opt out of capture, see limitations). Linux and macOS hosts are not implemented yet.
- **Easy, safe joining.** The host shows a QR code (or a link). A guest scans it, the host approves the device, and
  every guest gets its own encryption key. The QR code carries a fingerprint of the host's identity, so a guest
  refuses to talk to an impostor and never even sends its one-time token to the wrong device.
- **Stays in sync.** Clocks are aligned NTP-style, each guest buffers by a shared delay (default 160 ms, adjustable),
  and slow clock drift is corrected by a tiny resampling adjustment (at most +-0.5%, inaudible).
- **Low-latency codec.** Opus at 48 kHz stereo, 10 ms frames, with packet-loss concealment.
- **Follows your output device.** If you connect or disconnect Bluetooth headphones, playback moves to the new
  default device automatically, including headphones that only support 44.1 kHz.
- **Tells you why you hear nothing.** On Windows, if the app is muted or turned way down in the Volume Mixer, the
  guest says so instead of showing "Playing in sync" over silence.
- **Local network only.** UDP for audio, TCP for pairing. No servers, no accounts, nothing leaves your network.

## Tested on

| Platform | Host (shares audio) | Guest (plays audio) | Notes |
|---|---|---|---|
| Windows 11 | yes | yes | Wi-Fi/LAN. Bluetooth output switching verified. |
| Android 13 (Moto G32) | yes, with YouTube Music | yes | Camera QR scanning verified. Host needs Android 10+. |
| Linux | **not implemented** | untested | Guest playback uses a cross-platform audio library and may work, but nothing has been built or run on Linux. Host capture needs a PulseAudio/PipeWire "monitor" source, which is not written yet. |
| macOS | **not implemented** | untested | Capturing system audio on macOS needs a virtual audio device or newer system APIs; not written. |
| iOS | not possible | not built | iOS does not let an app capture other apps' audio, so it could only ever be a guest. |

Everything was measured on one phone, one PC and one home Wi-Fi network. Other hardware may behave differently.

## How it works

```
Host:   capture audio -> Opus encode (10 ms) -> timestamp -> encrypt per guest -> UDP
Guest:  UDP -> decrypt -> jitter buffer -> Opus decode -> drift-corrected playout (at host time + shared delay)
Pairing: QR/link -> Noise XX handshake over TCP (identity pinned by fingerprint) -> host approves -> per-guest key
Sync:   guest pings host; lowest round-trip sample gives the clock offset; drift controller keeps the queue steady
```

Audio and control packets are encrypted and authenticated with ChaCha20-Poly1305 using a separate key per guest.

## Repository layout

```
core/                 Rust workspace (the engine)
  mpsp-core/          packet format, clock sync, jitter buffer, drift correction, pairing (no audio hardware)
  mpsp-engine/        host and guest sessions, audio I/O, device switching, OS mixer checks
  mpsp-ffi/           C interface for Flutter (dart:ffi) and JNI for Android
  mpsp-cli/           terminal host/guest tool, handy for testing
  build-android.ps1   builds the engine for Android ABIs into the app
app/                  Flutter app (Windows, Android; other targets scaffolded)
```

The `mpsp-` crate prefix is a historical working name and may be renamed.

## Building from source

You need Rust (stable), a recent stable Flutter, and CMake (the Opus codec builds through it).
On Windows also install the Visual Studio Build Tools with the C++ workload.

**Engine and tests**

```
cd core
cargo test --workspace
cargo build --release -p mpsp-ffi        # the library the app loads
```

**Windows app**

```
cd app
# PowerShell: point the bundle step at the engine library you just built
$env:MPSP_FFI_DLL = "<path to>\mpsp_ffi.dll"
flutter build windows --release
```

**Android app** (needs the Android SDK and NDK r27, JDK 17, `cargo install cargo-ndk`,
`rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android`, and Ninja)

```
cd core
./build-android.ps1                      # fills app/android/app/src/main/jniLibs/
cd ../app
flutter build apk
```

**Dart tests that use the real engine** run against your built library:

```
cd app
$env:MPSP_FFI_PATH = "<path to>\mpsp_ffi.dll"
flutter test
```

**Windows build tips, learned the hard way**
- Opus fails to build with `path too long` errors under deep folders: set `CARGO_TARGET_DIR` to a short path such as `C:\rt`.
- With CMake 4, set `CMAKE_POLICY_VERSION_MINIMUM=3.5` for the Opus build.
- Run cargo from PowerShell, not Git Bash (Git's `link` shadows the MSVC linker).
- If Gradle fails with `Unable to establish loopback connection`, set `TEMP` and `TMP` to a short, plain folder.

## Known limitations

- **Android capture is up to each app.** Since Android 10, apps decide whether others may capture their audio, and
  many streaming apps opt out; those play silence. YouTube Music worked on the test phone. Others are untested.
- **Wi-Fi jitter sets the minimum latency.** On the test phone, plain pings to the router spiked to about 77 ms, so
  80 ms of buffer gave about 9% late packets and 140 ms or more gave none. The default is 160 ms; lower it on good
  networks. Bluetooth is deliberately not used as a transport because it cannot be synchronized tightly.
- **Android guests need the screen on** for the best Wi-Fi mode and have no background service yet.
- **Pairings are not remembered.** Guests re-scan after a restart.
- **Key storage is basic.** A host's long-term identity key is a plain file in its data folder. It should move to the
  operating system's key store.
- **Resampling is linear.** It keeps the pitch correct but a better filter would be gentler on high frequencies.
- **Android QR scanning uses Google ML Kit**, a proprietary component. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
- **Single local network.** No relay, no NAT traversal, no multi-subnet discovery.

## Security

Pairing uses the Noise XX pattern (via the `snow` crate), with the host's identity pinned by a fingerprint in the QR
code and a single-use token, and with explicit approval by the host for every device. Packets are encrypted per guest.
This is a small, young implementation that has **not been audited**. See [SECURITY.md](SECURITY.md) for how to report
a problem.

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE). Third-party components and their licenses are
listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
