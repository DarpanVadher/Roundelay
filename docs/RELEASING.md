# Releasing Roundelay (standard operating procedure)

One tag produces one release for every platform. Nothing is published automatically: the pipeline creates a **draft**
that a maintainer tests and then publishes.

| Platform | File | Status |
|---|---|---|
| Windows 10/11 x64 | `Roundelay-Setup-X.Y.Z.exe` (installer), `Roundelay-X.Y.Z-windows-x64.zip` (portable) | Supported (host and guest) |
| Android 5.0+ | `Roundelay-X.Y.Z-android-arm64.apk` (also `-armv7`, `-x86_64`, and a `.aab`) | Supported (host and guest) |
| Linux x64 | `Roundelay-X.Y.Z-linux-x64.tar.gz` | Experimental, guest only |
| macOS (Apple silicon and Intel) | `Roundelay-X.Y.Z-macos-universal.zip` | Experimental, guest only, not notarized |
| iOS | none | Not distributable until an Apple Developer account exists; CI only checks that it compiles |

## Versioning rules

- [Semantic Versioning](https://semver.org/): `MAJOR.MINOR.PATCH`. While we are on `0.x`, a minor bump may change behavior.
- Pre-releases use a suffix: `0.2.0-rc.1`. They are published as GitHub "pre-release" and never become "latest".
- The **git tag** is `v` + version (`v0.2.0`). The version must be identical in three places, and the pipeline
  refuses to build if they differ:
  1. `version` under `[workspace.package]` in `core/Cargo.toml`
  2. `version:` in `app/pubspec.yaml` (the part before `+`)
  3. a `## [X.Y.Z]` section in `CHANGELOG.md`
- The build number (Android `versionCode`, Windows/macOS build) is the workflow run number, so it always increases.

## Routine release

1. **Make sure `main` is green** and contains everything you want to ship.
2. **Open a release pull request** from a branch `release/vX.Y.Z` that only:
   - bumps the two version numbers above,
   - turns `## [Unreleased]` in `CHANGELOG.md` into `## [X.Y.Z] - YYYY-MM-DD` (and adds a fresh empty Unreleased section),
   - updates the compare links at the bottom of the changelog.
   Wait for CI, merge by squash or rebase (`main` is protected; nobody pushes directly).
3. **Optional dry run:** Actions, Release, "Run workflow", enter the version. Everything builds and the files are
   attached to the run as artifacts; no release is created. Use this when you changed build scripts.
4. **Tag the merge commit** and push the tag:
   ```bash
   git checkout main && git pull
   git tag -a vX.Y.Z -m "Roundelay X.Y.Z"
   git push origin vX.Y.Z
   ```
5. **Watch the Release workflow.** It verifies versions, runs the tests, builds all platforms, writes
   `SHA256SUMS.txt`, adds build-provenance attestations, and creates a draft release.
6. **Smoke-test the draft on real hardware** (download the draft's files, not your local build):
   - [ ] Windows installer: install, launch from the Start menu, no "demo mode" banner (the engine library loaded); also unzip the portable zip and run it.
   - [ ] Android APK on a phone: installs over the previous release (same signing key), app opens.
   - [ ] Pair Windows host to Android guest by QR, play audio for a minute: no silence, no repeated glitches.
   - [ ] Pair Android host to a second device if the release touched capture.
   - [ ] Linux/macOS: starts and shows the guest screen (experimental, best effort).
   - [ ] `sha256sum -c SHA256SUMS.txt` passes.
   Per the project's rule, measure; do not publish on "seems fine".
7. **Publish:** edit the draft's notes if needed, then click Publish release. Publishing triggers the landing page
   redeploy, which updates the download buttons.
8. **Verify the landing page:** open the site, check the version number and that every download link works.
9. **Announce** (README badge is automatic; post wherever you announce).

## Hotfix

Branch from the release tag (`git checkout -b release/vX.Y.(Z+1) vX.Y.Z`), apply the minimal fix, then follow the
routine from step 2 with a patch bump. Merge the fix back into `main` too.

## Rollback

Never delete or move a published tag, and never replace files of a published release (people verify checksums).
If a release is bad: edit it and tick "Set as a pre-release" (so it stops being "latest"), publish a fixed patch
release, and say what was wrong in the notes. Delete a release only if it contains something that must not be public
(for example a leaked secret), and rotate that secret.

## One-time setup (repository owner)

1. **Android signing key.** Create it once, keep a backup somewhere safe and private. If it is lost, users cannot
   update, they must uninstall first.
   ```bash
   keytool -genkeypair -v -keystore roundelay-release.jks -alias roundelay -keyalg RSA -keysize 4096 -validity 10000
   base64 -w0 roundelay-release.jks   # on Windows PowerShell: [Convert]::ToBase64String([IO.File]::ReadAllBytes("roundelay-release.jks"))
   ```
   Add these **repository secrets** (Settings, Secrets and variables, Actions): `ANDROID_KEYSTORE_BASE64`
   (the base64 text), `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` (`roundelay`), `ANDROID_KEY_PASSWORD`.
   Never commit the keystore (`.gitignore` covers `*.jks`, `*.keystore`, `key.properties`). A tagged release fails
   on purpose if the secret is missing, so a debug-signed APK can never be published.
   For local release builds create `app/android/key.properties` with `storeFile`, `storePassword`, `keyAlias`, `keyPassword`.
2. **GitHub Pages:** Settings, Pages, Source = "GitHub Actions".
3. **Who can tag:** add a tag ruleset (Settings, Rules) restricting creation of `v*` tags to maintainers.
4. **Optional later:** Windows code-signing certificate, Apple Developer account (macOS notarization, iOS), an
   an AppImage for Linux.

## What the pipeline does not do (be honest in release notes)

- Windows and macOS downloads are unsigned: expect SmartScreen and Gatekeeper warnings (macOS: right-click, Open).
- Linux and macOS are guests only; capture on those hosts is not implemented.
- No automatic update: users download the new version.
