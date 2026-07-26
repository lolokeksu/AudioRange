<p align="center">
  <img src="docs/assets/splash.svg" width="100%" alt="AudioRange — adaptive Android media volume steps">
</p>

<p align="center">
  <a href="https://github.com/lolokeksu/AudioRange/releases/tag/v1.0.0-beta.1"><img alt="Release v1.0.0-beta.1" src="https://img.shields.io/badge/release-v1.0.0--beta.1-6366f1"></a>
  <a href="https://github.com/lolokeksu/AudioRange/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/lolokeksu/AudioRange/actions/workflows/ci.yml/badge.svg"></a>
  <img alt="Android 13–16" src="https://img.shields.io/badge/Android-13--16-3ddc84?logo=android&logoColor=white">
  <a href="LICENSE"><img alt="MIT" src="https://img.shields.io/badge/license-MIT-64748b"></a>
</p>

<p align="center"><a href="README_RU.md">Русский</a> · <a href="https://github.com/lolokeksu/AudioRange/releases">Releases</a> · <a href="SECURITY.md">Security</a></p>

---

# AudioRange

AudioRange is a systemless Android root module that changes the logical `STREAM_MUSIC` step count and verifies the result against the real Android `AudioService` range.

## Release status

**v1.0.0-beta.1 is the first public beta.** The project has its own version history and build/release pipeline. It does not require another module or upstream runtime component.

Verified target:

| Device | Android | Root | Result |
|---|---:|---|---|
| Realme GT Neo 5 SE / RMX3700 | 13 / API 33 | APatch | `STREAM_MUSIC 0–30` confirmed |

Other firmware and root managers remain experimental until real device reports are available.

## What it changes

The module sets only:

```properties
ro.config.media_vol_steps
```

It applies the property systemlessly through `system.prop` and early `post-fs-data.sh`, then validates the effective maximum through:

```sh
cmd media_session volume --stream 3 --get
```

It does not increase amplifier power, patch framework JAR files, change Audio HAL/Audio Policy, disable SELinux, modify AVB or write boot partitions.

## Adaptive compatibility

Results are keyed to the exact firmware fingerprint and stored locally in `/data/adb/audiorange/compatibility.conf`. Unknown firmware starts unverified. Values confirmed or rejected on one fingerprint are not transferred to another after OTA.

The bundled RMX3700 maximum of 30 is matched only against the exact researched firmware fingerprint. It is not a global limit for Realme, OPPO, OnePlus or Android.

## Interfaces

- compact WebUI for APatch and KernelSU;
- read-only Manager Action;
- CLI: `su -c audiorange`;
- profiles: Stock, 30, 50, 75, 100 and custom 15–100;
- diagnostics, integrity verification, conflict scan, reports and history;
- safe temporary volume test with automatic restoration.

## Installation

Install the release ZIP through APatch, KernelSU or Magisk and reboot. Then run:

```sh
su -c audiorange check
su -c audiorange doctor
```

For recovery:

```sh
su -c audiorange stock
su -c reboot
```

A bootloop can be handled by creating `/data/adb/modules/audiorange/disable` from recovery/ADB or by removing the module directory.

## Build

```sh
./scripts/test.sh
./scripts/build.sh
```

Deterministic module/source archives and `SHA256SUMS` are written to `dist/`.

## Project files

- `module/` — installable module source;
- `scripts/` — tests and deterministic release build;
- `docs/assets/splash.svg` — standalone project splash;
- `COMPATIBILITY.md` — verified and experimental environments;
- `TESTING.md` — device report protocol;
- `PRIVACY.md` and `SECURITY.md` — data and security boundaries.
