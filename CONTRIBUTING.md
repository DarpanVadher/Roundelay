# Contributing to Roundelay

Thanks for helping. This project is young, so small, well-tested changes are the easiest to review.

## Getting set up

Follow "Building from source" in the [README](README.md). Before opening a pull request, run:

```
cd core && cargo test --workspace
cd ../app && flutter analyze && flutter test
```

`flutter test` includes tests that load the real engine library; point `MPSP_FFI_PATH` at your built
`mpsp_ffi` library, otherwise those tests are skipped (and say so). Please do not add tests that pass by being
skipped, or that only restate the code they test.

## How we work

- **Measure before you claim.** Audio bugs here have repeatedly turned out to be somewhere other than where the
  first guess put them (the Wi-Fi link, a muted OS mixer, a broken test tool). If you are fixing a glitch, include
  the numbers that show the cause and the numbers that show it is fixed. The engine has built-in diagnostics:
  `MPSP_TRACE`, `MPSP_AUDIO_TRACE`, `MPSP_AUDIO_DUMP`, and the `diag`, `replay` and `devices` examples in
  `core/mpsp-engine/examples/`.
- **Keep changes focused.** One concern per pull request, with a test for the behavior you changed or added.
- **Real hardware matters.** Say what you tested on (OS, device, network). "Works on my machine" is useful when it
  names the machine.
- **No secrets or personal data.** Never commit host keys (`host_key.bin`), keystores, `local.properties`, or
  captured audio and traces from your own network. The `.gitignore` covers the usual ones; check your diff anyway.
- **Security-sensitive changes** (pairing, keys, packet formats) need extra care and a clear description of the
  threat they address. To report a vulnerability, see [SECURITY.md](SECURITY.md) instead of opening a public issue.

## Where help is most wanted

- Linux host capture (a PulseAudio/PipeWire monitor source) and guest verification, macOS host capture, iOS guest
  support, and testing on more phones, PCs and networks.
- An Android foreground service so guests can play with the screen off.
- Remembering paired devices, and moving the host key to the OS key store.
- A replacement for the ML Kit QR scanner so Android builds can be fully open source.
- A higher-quality resampler for devices that do not run at 48 kHz.

## Licensing of contributions

Unless you state otherwise, any contribution you submit is licensed under the Apache License 2.0, the same as the
project (see section 5 of the [LICENSE](LICENSE)). Only submit work you have the right to contribute.
