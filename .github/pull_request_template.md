## What this changes and why

<!-- One concern per pull request. Link an issue if there is one. -->

## How it was tested

<!-- Which OS, device and network? For audio problems, include the numbers that show the cause and the fix. -->

- [ ] `cargo test --workspace` passes in `core/`
- [ ] `flutter analyze` and `flutter test` pass in `app/` (with `MPSP_FFI_PATH` set if the change touches the engine interface)
- [ ] Tested on real hardware: <!-- e.g. Windows 11 + Pixel 7, home Wi-Fi -->

## Checklist

- [ ] No secrets, keys, personal data, captured audio or traces in the diff
- [ ] Security-sensitive changes (pairing, keys, packet format) explain the threat they address
- [ ] I have the right to contribute this, under the project's Apache-2.0 license
