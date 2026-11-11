# Third-party notices

Roundelay's own code is licensed under the Apache License 2.0 (see `LICENSE`). It builds on the open-source
components below. This list covers the components that matter most for distribution; it is not a full
inventory of every transitive dependency. To regenerate a complete list, run `cargo about` or `cargo deny list`
in `core/`, and `flutter pub deps` in `app/`.

## Components that need an explicit notice

### Opus codec (libopus) - BSD 3-Clause
Bundled and compiled into the engine through the `audiopus_sys` crate. BSD-3-Clause requires this notice to be
reproduced in documentation or other materials provided with binary distributions:

```
Copyright 2001-2011 Xiph.Org, Skype Limited, Octasic,
                    Jean-Marc Valin, Timothy B. Terriberry,
                    CSIRO, Gregory Maxwell, Mark Borgerding,
                    Erik de Castro Lopo

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:

- Redistributions of source code must retain the above copyright
notice, this list of conditions and the following disclaimer.

- Redistributions in binary form must reproduce the above copyright
notice, this list of conditions and the following disclaimer in the
documentation and/or other materials provided with the distribution.

- Neither the name of Internet Society, IETF or IETF Trust, nor the
names of specific contributors, may be used to endorse or promote
products derived from this software without specific prior written
permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER
OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

Opus is subject to the royalty-free patent licenses which are
specified at:

Xiph.Org Foundation:
https://datatracker.ietf.org/ipr/1524/

Microsoft Corporation:
https://datatracker.ietf.org/ipr/1914/

Broadcom Corporation:
https://datatracker.ietf.org/ipr/1526/
```

### Google ML Kit barcode scanning - proprietary (Android QR scanner)
On Android the QR-code scanner (`mobile_scanner`) links **Google ML Kit** (`com.google.mlkit:barcode-scanning`),
which is **not open source** and is governed by Google's terms. The `mobile_scanner` plugin itself is BSD 3-Clause.
By default the ML Kit model is bundled in the app (about 3-10 MB). A build that must contain only open-source
components (for example for F-Droid) has to replace the scanner with an open decoder such as ZXing, or disable
the camera scanner and rely on pasting the pairing link, which the app supports.

## Permissively licensed dependencies (summary)

| Component | Used for | License |
|---|---|---|
| cpal | Audio input/output on desktop and Android | Apache-2.0 |
| Oboe (via cpal) | Android audio backend (C++) | Apache-2.0 |
| snow | Noise protocol (pairing handshake) | Apache-2.0 OR MIT |
| chacha20poly1305 (RustCrypto) | Encrypting audio and control packets | Apache-2.0 OR MIT |
| sha2, rand | Hashing, random numbers | MIT OR Apache-2.0 |
| serde, serde_json | Event serialization | MIT OR Apache-2.0 |
| anyhow | Error handling | MIT OR Apache-2.0 |
| windows (windows-rs) | Windows audio session API | MIT OR Apache-2.0 |
| jni, ndk-context | Android JNI glue | MIT OR Apache-2.0 |
| qrcode (Rust) | QR code in the terminal tool | MIT OR Apache-2.0 |
| Flutter framework and engine | App UI | BSD 3-Clause |
| qr_flutter | Showing the pairing QR code | BSD 3-Clause |
| mobile_scanner | Camera QR scanning (see ML Kit above) | BSD 3-Clause |
| ffi (Dart) | Calling the engine library | BSD 3-Clause |
| cupertino_icons | Icons | MIT |

The landing page in `site/` (not part of the app) serves two fonts from `site/fonts/`: **Bricolage Grotesque**
and **Figtree**, both under the SIL Open Font License 1.1.

An audit of the Rust dependency tree (all crates, including transitive ones) found only permissive licenses
(MIT, Apache-2.0, BSD, ISC, Zlib, Unicode, Unlicense, CC0-style). One crate (`r-efi`) offers an optional
`LGPL-2.1-or-later` alternative alongside MIT and Apache-2.0; Roundelay uses it under MIT/Apache-2.0.
