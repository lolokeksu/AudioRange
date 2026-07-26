# Security policy

## Supported versions

Security fixes are provided for the latest beta or stable release only.

## Reporting

Open a private GitHub security advisory when possible. Include the affected version, root manager, Android version, reproduction steps and relevant logs. Do not publish device identifiers or firmware fingerprints unless necessary.

## Security boundaries

The project does not modify SELinux, AVB, dm-verity, certificates, DNS, hosts, boot images or dynamic partitions. It does not download or execute remote code. Unknown binary files are not part of the release.
