# Agent instructions

## Project contract

This repository builds a bootable Orange Pi PC 2 Armbian image for an
AI-native embedded debug host. Keep the build reproducible, keep credentials
out of Git, and distinguish image inspection from physical-board validation.

The maintained entry points are:

- `image.conf`: pinned upstream image, hash, image size, identity, and runtime versions.
- `packages.txt`: one Debian package per line; this is also installed into the image.
- `pi-help`: agent-readable live inventory and evidence contract.
- `build-on-macos.sh`: full macOS build through Apple Container.
- `build-linux.sh`: full native ARM64 Linux/GitHub Actions build.
- `customize-image.sh`, `verify-image.sh`, `compress-image.sh`: root-only stages.

## Credentials and generated files

- Never commit `.envrc`, `authorized_key.pub`, a private key, an encoded key,
  disk images, captures, or build output.
- Local builds receive only a public key through `SSH_PUBLIC_KEY_FILE`, normally
  exported by `.envrc`. Do not source a user's private environment file from a script.
- GitHub Actions receives the base64-encoded public key through the repository
  secret `SSH_PUBLIC_KEY_B64`. Base64 is transport encoding, not encryption.
- Validate the input as an OpenSSH public key. Never print the key itself; a
  fingerprint from `ssh-keygen -l` is acceptable.

## Changing the image

1. Change pins and defaults in `image.conf`; preserve and verify the official
   upstream SHA-256 before modifying an image.
2. Change Debian packages only in `packages.txt`. Ensure `pi-help packages`
   reports every item dynamically using `dpkg-query`.
3. When adding a tool outside APT, pin its version, verify it inside the chroot,
   expose its version through `pi-help`, and add an assertion to `verify-image.sh`.
4. If SSH, sudo, users, first-boot behavior, services, or permissions change,
   add a verifier assertion in the same change.
5. Keep system Python owned by Debian. Install optional newer Python versions
   through uv in the unprivileged `debug` user's home.
6. Run shell syntax/static checks, then the full image verifier. A build is not
   complete merely because package installation succeeded.

Use `output/` for all downloads and generated artifacts. Reuse the pinned
compressed base image, but regenerate the writable raw image for each build.
Ensure loop devices and mounts are released on every exit. Do not delete a
user's existing image or unrelated files; `FORCE=1` authorizes replacement of
only the named generated output.

## Validation and evidence boundaries

The automated verifier proves filesystem content, package state, effective
sshd policy, key placement, locked passwords, service enablement, first-boot
markers, `pi-help` output, and ext4 consistency. Container/QEMU inspection does
not prove that the Allwinner H5 boots, Ethernet works, a USB device negotiates
full/high speed, packets are lossless, Bluetooth RF is captured, or latency
targets are met. Report these as separate physical-board gates.

Before flashing, identify the exact removable disk and obtain explicit user
authorization for that target. Never infer a `/dev/diskN` or `/dev/sdX` name.
The 6 GiB image fits a 32 GB card; Armbian expands the root filesystem on first boot.

## Release flow

Local: copy `.envrc.example` to `.envrc`, adjust the public-key path, run
`direnv allow`, then `make build`. GitHub: configure `SSH_PUBLIC_KEY_B64`, run
the manual workflow, and inspect its verifier output. A `v*` tag additionally
creates a GitHub Release. Do not tag or publish a release unless requested.
