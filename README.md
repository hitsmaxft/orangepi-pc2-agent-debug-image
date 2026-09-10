# orangepi-pc2-agent-debug-image

Reproducible Armbian image for turning an Orange Pi PC 2 into an isolated,
AI-native embedded USB/Bluetooth debug host. It is designed for USBFS/USBHS,
HID, serial, probe/flashing, HCI capture, and optional RF-sniffer workflows
without exposing a macOS development machine directly to experimental devices.

## Image profile

- Orange Pi PC 2 / Allwinner H5 / AArch64
- Armbian 26.8.1 Minimal, Debian 13 trixie, Linux 6.18.44
- User `debug`, hostname `opi-pc2-debug`
- Public-key-only SSH, limited to loopback/private LAN address ranges
- Locked `root` and `debug` passwords; root SSH disabled
- `debug` has passwordless sudo: `NOPASSWD: ALL`
- Debian system Python 3.13 plus uv-managed CPython 3.14.7 and uv 0.12.12
- `pi-help` gives agents a live tool/version/hardware inventory and evidence contract

The board supports USB 2.0 full speed and high speed, not USB 3.x SuperSpeed.
It has no onboard Bluetooth radio: HCI work needs a USB Bluetooth adapter, and
over-the-air sniffing needs dedicated hardware such as Ubertooth or a Nordic sniffer.

## Local build on macOS

Apple's `container` CLI, `curl`, `xz`, `shasum`, and `direnv` are required.
The build runs an ARM64 Debian container so the target chroot can execute natively.

```sh
git clone https://github.com/hitsmaxft/orangepi-pc2-agent-debug-image.git
cd orangepi-pc2-agent-debug-image
cp .envrc.example .envrc
# Edit SSH_PUBLIC_KEY_FILE if ~/.ssh/id_ed25519.pub is not your default key.
direnv allow
make build
```

The build downloads the pinned official image into `output/`, checks its
SHA-256, creates a fresh raw image, customizes it, runs the full verifier,
zeroes free ext4 blocks for compression, and writes:

```text
output/*-usb-debug.img.xz
output/SHA256SUMS
```

Set `FORCE=1 make build` to replace only the existing generated output image.
The public key, `.envrc`, raw/compressed images, and checksums are gitignored.

## GitHub Actions build

The public key is transported as a base64-encoded repository secret. Although
it is only a public key, using a secret avoids embedding one developer identity
in source history.

```sh
base64 <"$HOME/.ssh/id_ed25519.pub" | tr -d '\n' | \
  gh secret set SSH_PUBLIC_KEY_B64 \
  --repo hitsmaxft/orangepi-pc2-agent-debug-image
```

Run **Build Armbian debug image** manually to receive a 14-day workflow
artifact. Pushing a requested `v*` tag runs the same verifier and publishes the
compressed image plus `SHA256SUMS` as a GitHub Release. The workflow uses the
native `ubuntu-24.04-arm` GitHub-hosted runner.

## Installed capabilities

- USB: usbutils, usbtop, usbip, usbmon, tshark/Wireshark, libusb, HIDAPI,
  PyUSB, evtest, and input-utils
- Bluetooth: BlueZ, `bluetoothctl`, `btmon`, BlueZ test/tools, libbluetooth,
  Ubertooth tools, and Scapy
- Probes/flashing: OpenOCD, ST-Link, dfu-util, flashrom, avrdude, sigrok-cli
- Serial/network: picocom, minicom, socat, ser2net (disabled by default),
  tcpdump, iperf3, and ethtool
- Development: GCC/G++, Clang/LLD, CMake, Ninja, pkg-config, gdb-multiarch,
  strace, Git, Python/venv/pipx, uv, and CPython 3.14

After SSH login, run `pi-help`, `pi-help packages`, or `pi-help workflows`.
The SSH MOTD points both humans and agents to this command.

## Flash a 32 GB microSD card

Verify `output/SHA256SUMS`, then flash the `.img.xz` directly with Raspberry Pi
Imager or balenaEtcher. These tools make it easier to identify the removable
card safely. Do not guess a raw disk path. A 32 GB card is sufficient; the raw
image is 6 GiB and Armbian expands the root filesystem on first boot.

```sh
cd output
shasum -a 256 -c SHA256SUMS
```

Connect wired Ethernet, boot, wait several minutes, then use:

```sh
ssh debug@opi-pc2-debug.local
```

If mDNS is unavailable, use the DHCP address from the router. SSH intentionally
rejects public Internet and CGNAT/Tailscale `100.64.0.0/10` source addresses.

## Verification boundary

`verify-image.sh` checks packages, SSH policy, locked passwords, key content and
modes, sudo, enabled services, unique-identity first-boot markers, `pi-help`,
and ext4 consistency. It does not prove physical H5 boot, USB electrical or
transfer behavior, Bluetooth RF capture, or end-to-end latency. Those remain
on-board acceptance gates; QEMU `virt` does not emulate this board's H5 SoC and
USB/Ethernet PHYs.

See [AGENTS.md](AGENTS.md) before an agent changes the build or validation contract.

## Upstream references

- [Armbian Orange Pi PC 2](https://www.armbian.com/orangepipc2/)
- [Armbian first-login customization](https://docs.armbian.com/User-Guide_Autoconfig/)
- [Orange Pi PC 2 hardware](https://www.orangepi.org/html/hardWare/computerAndMicrocontrollers/details/Orange-Pi-PC-2.html)
- [GitHub-hosted runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
- [GitHub Actions secrets](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets)

## License

Build scripts are MIT licensed. Armbian and installed packages retain their own licenses.
