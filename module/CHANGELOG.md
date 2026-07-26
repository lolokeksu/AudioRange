# Changelog

## v1.0.0-beta.1 — Initial beta

- Initial public beta of AudioRange.
- Added adaptive compatibility keyed to the exact firmware fingerprint.
- Added runtime verification through Android `AudioService`; `getprop` alone is never treated as proof.
- Added profiles Stock, 30, 50, 75, 100 and validated custom values from 15 to 100.
- Added compact WebUI for APatch and KernelSU, read-only Manager Action and the `audiorange` CLI.
- Added early property application through `post-fs-data.sh` and `resetprop -n`.
- Added safe volume testing with timed restoration, integrity checks, diagnostics, history and reports.
- Added a verified RMX3700 firmware rule with an OEM maximum of 30 steps; it is not applied to other fingerprints.
- Added reproducible source/module builds, CI, release automation and a standalone SVG project splash.

### Beta scope

The core result `STREAM_MUSIC 0–30` is verified on Realme GT Neo 5 SE, Android 13, Realme UI 4.0 and APatch. Other devices, Android 14–16 and other root managers require device reports before stable status.
