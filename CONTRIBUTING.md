# Contributing

Use a focused pull request with one behavioral change. Run `./scripts/test.sh` and `./scripts/build.sh` before submitting.

Device compatibility claims require the output of `audiorange doctor`, the real `AudioService` range and the exact firmware fingerprint. Brand-level assumptions are not accepted as proof.

Do not add framework patches, remote downloaders, telemetry or automatic reboot loops.
