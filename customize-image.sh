#!/bin/bash
set -Eeuo pipefail

IMAGE=${1:?usage: customize-image.sh IMAGE AUTHORIZED_KEY_FILE}
AUTHORIZED_KEY_FILE=${2:?usage: customize-image.sh IMAGE AUTHORIZED_KEY_FILE}
IMAGE_SIZE=${IMAGE_SIZE:-6G}
TARGET_USER=${TARGET_USER:-debug}
TARGET_HOSTNAME=${TARGET_HOSTNAME:-opi-pc2-debug}
UV_VERSION=${UV_VERSION:-0.12.12}
PYTHON_VERSION=${PYTHON_VERSION:-3.14.7}
PROJECT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PACKAGES_FILE=${PACKAGES_FILE:-$PROJECT_DIR/packages.txt}
WORKDIR=$(mktemp -d /tmp/opi-image.XXXXXX)
LOOPDEV=

cleanup() {
    set +e
    for path in run proc sys dev/pts dev; do
        mountpoint -q "$WORKDIR/root/$path" && umount -l "$WORKDIR/root/$path"
    done
    mountpoint -q "$WORKDIR/root" && umount -l "$WORKDIR/root"
    [[ -n "$LOOPDEV" ]] && losetup -d "$LOOPDEV"
    rm -rf "$WORKDIR"
}
trap cleanup EXIT

[[ -f "$IMAGE" ]] || { echo "image not found: $IMAGE" >&2; exit 1; }
[[ -s "$AUTHORIZED_KEY_FILE" ]] || { echo "public key not found: $AUTHORIZED_KEY_FILE" >&2; exit 1; }
[[ -s "$PACKAGES_FILE" ]] || { echo "package list not found: $PACKAGES_FILE" >&2; exit 1; }
grep -Eq '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp)' "$AUTHORIZED_KEY_FILE" || {
    echo "not an OpenSSH public key: $AUTHORIZED_KEY_FILE" >&2
    exit 1
}

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    fdisk parted util-linux e2fsprogs

current_size=$(stat -c %s "$IMAGE")
requested_size=$(numfmt --from=iec "$IMAGE_SIZE")
if (( requested_size > current_size )); then
    truncate -s "$IMAGE_SIZE" "$IMAGE"
    parted -s "$IMAGE" resizepart 1 100%
fi

LOOPDEV=$(losetup --find --show --partscan "$IMAGE")
ROOT_PART="${LOOPDEV}p1"
for _ in $(seq 1 20); do
    [[ -b "$ROOT_PART" ]] && break
    sleep 0.25
done
[[ -b "$ROOT_PART" ]] || { echo "partition device missing: $ROOT_PART" >&2; exit 1; }

e2fsck -fy "$ROOT_PART"
resize2fs "$ROOT_PART"
mkdir -p "$WORKDIR/root"
mount "$ROOT_PART" "$WORKDIR/root"

for path in dev dev/pts proc sys run; do
    mount --rbind "/$path" "$WORKDIR/root/$path"
    mount --make-rslave "$WORKDIR/root/$path"
done
# Armbian uses systemd-resolved's stub path. The build container has no
# systemd-resolved, so provide its DNS file at the path used by the chroot.
mkdir -p "$WORKDIR/root/run/systemd/resolve"
cp /etc/resolv.conf "$WORKDIR/root/run/systemd/resolve/stub-resolv.conf"

install -m 0755 /bin/true "$WORKDIR/root/usr/sbin/policy-rc.d"
cat >"$WORKDIR/root/usr/sbin/policy-rc.d" <<'EOF'
#!/bin/sh
exit 101
EOF

export DEBIAN_FRONTEND=noninteractive
chroot "$WORKDIR/root" debconf-set-selections <<'EOF'
wireshark-common wireshark-common/install-setuid boolean true
EOF
chroot "$WORKDIR/root" apt-get update
mapfile -t packages < <(grep -Ev '^[[:space:]]*(#|$)' "$PACKAGES_FILE")
chroot "$WORKDIR/root" apt-get install -y --no-install-recommends "${packages[@]}"

rm -f "$WORKDIR/root/usr/sbin/policy-rc.d"

for group in sudo plugdev dialout bluetooth wireshark input; do
    chroot "$WORKDIR/root" getent group "$group" >/dev/null || chroot "$WORKDIR/root" groupadd "$group"
done
if ! chroot "$WORKDIR/root" id "$TARGET_USER" >/dev/null 2>&1; then
    chroot "$WORKDIR/root" useradd --create-home --shell /bin/bash "$TARGET_USER"
fi
chroot "$WORKDIR/root" usermod -aG sudo,plugdev,dialout,bluetooth,wireshark,input "$TARGET_USER"
chroot "$WORKDIR/root" passwd -l "$TARGET_USER"
chroot "$WORKDIR/root" passwd -l root

chroot "$WORKDIR/root" env \
    UV_UNMANAGED_INSTALL=/usr/local/bin \
    UV_NO_MODIFY_PATH=1 \
    sh -c "curl --proto '=https' --tlsv1.2 -LsSf https://releases.astral.sh/github/uv/releases/download/$UV_VERSION/uv-installer.sh | sh"
chroot "$WORKDIR/root" runuser -u "$TARGET_USER" -- env \
    HOME="/home/$TARGET_USER" \
    /usr/local/bin/uv python install "$PYTHON_VERSION" --no-cache
chroot "$WORKDIR/root" /usr/local/bin/uv --version
chroot "$WORKDIR/root" "/home/$TARGET_USER/.local/bin/python3.14" --version

install -d -m 0700 -o "$(chroot "$WORKDIR/root" id -u "$TARGET_USER")" \
    -g "$(chroot "$WORKDIR/root" id -g "$TARGET_USER")" \
    "$WORKDIR/root/home/$TARGET_USER/.ssh"
install -m 0600 -o "$(chroot "$WORKDIR/root" id -u "$TARGET_USER")" \
    -g "$(chroot "$WORKDIR/root" id -g "$TARGET_USER")" \
    "$AUTHORIZED_KEY_FILE" "$WORKDIR/root/home/$TARGET_USER/.ssh/authorized_keys"

cat >"$WORKDIR/root/etc/sudoers.d/90-$TARGET_USER" <<EOF
$TARGET_USER ALL=(ALL:ALL) NOPASSWD: ALL
EOF
chmod 0440 "$WORKDIR/root/etc/sudoers.d/90-$TARGET_USER"

install -d -m 0755 "$WORKDIR/root/etc/ssh/sshd_config.d"
cat >"$WORKDIR/root/etc/ssh/sshd_config.d/90-lan-public-key-only.conf" <<EOF
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
AuthenticationMethods publickey
PermitRootLogin no
AllowUsers $TARGET_USER@127.0.0.0/8 $TARGET_USER@10.0.0.0/8 $TARGET_USER@172.16.0.0/12 $TARGET_USER@192.168.0.0/16 $TARGET_USER@::1 $TARGET_USER@fc00::/7 $TARGET_USER@fe80::/10
EOF

echo "$TARGET_HOSTNAME" >"$WORKDIR/root/etc/hostname"
sed -i -E "s/^127\.0\.1\.1.*/127.0.1.1\t$TARGET_HOSTNAME/" "$WORKDIR/root/etc/hosts"

cat >"$WORKDIR/root/etc/udev/rules.d/70-embedded-debug.rules" <<'EOF'
# Dedicated lab host: let the plugdev group access USB devices and raw HID.
SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", MODE="0660", GROUP="plugdev"
KERNEL=="hidraw*", MODE="0660", GROUP="plugdev"
KERNEL=="usbmon[0-9]*", MODE="0640", GROUP="wireshark"
EOF
cat >"$WORKDIR/root/etc/modules-load.d/embedded-debug.conf" <<'EOF'
usbmon
EOF

cat >"$WORKDIR/root/usr/local/sbin/opi-debug-firstboot" <<'EOF'
#!/bin/sh
set -eu
ssh-keygen -A
systemd-machine-id-setup
rm -f /var/lib/dbus/machine-id
ln -s /etc/machine-id /var/lib/dbus/machine-id
rm -f /var/lib/opi-debug-firstboot
EOF
chmod 0755 "$WORKDIR/root/usr/local/sbin/opi-debug-firstboot"
cat >"$WORKDIR/root/etc/systemd/system/opi-debug-firstboot.service" <<'EOF'
[Unit]
Description=Generate unique identity and SSH host keys
ConditionPathExists=/var/lib/opi-debug-firstboot
Before=ssh.service
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/opi-debug-firstboot

[Install]
WantedBy=multi-user.target
EOF
touch "$WORKDIR/root/var/lib/opi-debug-firstboot"

rm -f "$WORKDIR/root/root/.not_logged_in_yet"
chroot "$WORKDIR/root" systemctl disable ser2net.service || true
chroot "$WORKDIR/root" systemctl enable ssh.service bluetooth.service avahi-daemon.service opi-debug-firstboot.service
install -d -m 0755 "$WORKDIR/root/run/sshd"
chroot "$WORKDIR/root" ssh-keygen -A
chroot "$WORKDIR/root" sshd -t
chroot "$WORKDIR/root" visudo -cf "/etc/sudoers.d/90-$TARGET_USER"

install -D -m 0755 "$PROJECT_DIR/pi-help" "$WORKDIR/root/usr/local/bin/pi-help"
install -D -m 0644 "$PACKAGES_FILE" \
    "$WORKDIR/root/usr/share/pi-debug-image/packages.txt"
cat >"$WORKDIR/root/etc/update-motd.d/99-pi-help" <<'EOF'
#!/bin/sh
echo "AI-native debug host: run 'pi-help' for tools, live environment, workflows, and evidence gates."
EOF
chmod 0755 "$WORKDIR/root/etc/update-motd.d/99-pi-help"

rm -f "$WORKDIR/root/etc/ssh/ssh_host_"*
: >"$WORKDIR/root/etc/machine-id"
rm -f "$WORKDIR/root/var/lib/dbus/machine-id"

chroot "$WORKDIR/root" apt-get clean
rm -rf "$WORKDIR/root/var/lib/apt/lists/"*
rm -rf "$WORKDIR/root/tmp/uv-cache" "$WORKDIR/root/root/.cache/uv" \
    "$WORKDIR/root/home/$TARGET_USER/.cache/uv"
sync

echo "customized image: $IMAGE"
