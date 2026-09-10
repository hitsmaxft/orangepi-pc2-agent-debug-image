#!/bin/bash
set -Eeuo pipefail

IMAGE=${1:?usage: verify-image.sh IMAGE AUTHORIZED_KEY_FILE}
AUTHORIZED_KEY_FILE=${2:?usage: verify-image.sh IMAGE AUTHORIZED_KEY_FILE}
PROJECT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PACKAGES_FILE=${PACKAGES_FILE:-$PROJECT_DIR/packages.txt}
WORKDIR=$(mktemp -d /tmp/opi-verify.XXXXXX)
LOOPDEV=

cleanup() {
    set +e
    mountpoint -q "$WORKDIR/root/mnt" && umount "$WORKDIR/root/mnt"
    mountpoint -q "$WORKDIR/root/run" && umount "$WORKDIR/root/run"
    mountpoint -q "$WORKDIR/root/proc" && umount -l "$WORKDIR/root/proc"
    mountpoint -q "$WORKDIR/root/sys" && umount -l "$WORKDIR/root/sys"
    mountpoint -q "$WORKDIR/root/dev" && umount -l "$WORKDIR/root/dev"
    mountpoint -q "$WORKDIR/root" && umount "$WORKDIR/root"
    [[ -n "$LOOPDEV" ]] && losetup -d "$LOOPDEV"
    rm -rf "$WORKDIR"
}
trap cleanup EXIT

mkdir -p "$WORKDIR/root" "$WORKDIR/key" "$WORKDIR/run/sshd"
ssh-keygen -q -t ed25519 -N '' -f "$WORKDIR/key/host_key"
LOOPDEV=$(losetup --find --show --partscan --read-only "$IMAGE")
ROOT_PART="${LOOPDEV}p1"
mount -o ro "$ROOT_PART" "$WORKDIR/root"
mount --rbind /dev "$WORKDIR/root/dev"
mount --make-rslave "$WORKDIR/root/dev"
mount --rbind /proc "$WORKDIR/root/proc"
mount --make-rslave "$WORKDIR/root/proc"
mount --rbind /sys "$WORKDIR/root/sys"
mount --make-rslave "$WORKDIR/root/sys"
mount --bind "$WORKDIR/run" "$WORKDIR/root/run"
mount --bind "$WORKDIR/key" "$WORKDIR/root/mnt"

[[ $(cat "$WORKDIR/root/etc/hostname") == opi-pc2-debug ]]
[[ ! -e "$WORKDIR/root/root/.not_logged_in_yet" ]]
[[ -e "$WORKDIR/root/var/lib/opi-debug-firstboot" ]]
[[ ! -s "$WORKDIR/root/etc/machine-id" ]]
! compgen -G "$WORKDIR/root/etc/ssh/ssh_host_*" >/dev/null

cmp -s "$AUTHORIZED_KEY_FILE" "$WORKDIR/root/home/debug/.ssh/authorized_keys"
[[ $(stat -c %a "$WORKDIR/root/home/debug/.ssh") == 700 ]]
[[ $(stat -c %a "$WORKDIR/root/home/debug/.ssh/authorized_keys") == 600 ]]
[[ $(chroot "$WORKDIR/root" /usr/local/bin/uv --version) == 'uv 0.12.12'* ]]
[[ $(chroot "$WORKDIR/root" /home/debug/.local/bin/python3.14 --version) == 'Python 3.14.7' ]]
[[ ! -d "$WORKDIR/root/home/debug/.cache/uv" ]]
[[ -x "$WORKDIR/root/usr/local/bin/pi-help" ]]
[[ -x "$WORKDIR/root/etc/update-motd.d/99-pi-help" ]]
chroot "$WORKDIR/root" /usr/local/bin/pi-help packages >"$WORKDIR/pi-help-packages"
grep -q '^usbutils.*installed$' "$WORKDIR/pi-help-packages"
grep -q '^python3.*installed$' "$WORKDIR/pi-help-packages"
! grep -q 'MISSING$' "$WORKDIR/pi-help-packages"
chroot "$WORKDIR/root" /usr/local/bin/pi-help all >"$WORKDIR/pi-help-all" 2>&1
grep -q '^PI_DEBUG_IMAGE_HELP_VERSION=1$' "$WORKDIR/pi-help-all"
grep -q '^\[agent_evidence_contract\]$' "$WORKDIR/pi-help-all"
grep -q '^sudo=debug has NOPASSWD ALL$' "$WORKDIR/pi-help-all"

while read -r package; do
    [[ -z "$package" || "$package" == \#* ]] && continue
    [[ $(chroot "$WORKDIR/root" dpkg-query -W -f='${db:Status-Abbrev}' "$package") == ii* ]]
done <"$PACKAGES_FILE"

chroot "$WORKDIR/root" sshd -T -h /mnt/host_key \
    -C user=debug,host=opi-pc2-debug,addr=192.168.1.2 >"$WORKDIR/sshd-effective"
grep -qx 'passwordauthentication no' "$WORKDIR/sshd-effective"
grep -qx 'kbdinteractiveauthentication no' "$WORKDIR/sshd-effective"
grep -qx 'pubkeyauthentication yes' "$WORKDIR/sshd-effective"
grep -qx 'permitrootlogin no' "$WORKDIR/sshd-effective"
grep -qx 'authenticationmethods publickey' "$WORKDIR/sshd-effective"

for service in ssh.service bluetooth.service avahi-daemon.service opi-debug-firstboot.service; do
    chroot "$WORKDIR/root" systemctl is-enabled "$service" >/dev/null
done
[[ $(chroot "$WORKDIR/root" systemctl is-enabled ser2net.service 2>/dev/null || true) == disabled ]]

debug_shadow=$(awk -F: '$1 == "debug" {print $2}' "$WORKDIR/root/etc/shadow")
root_shadow=$(awk -F: '$1 == "root" {print $2}' "$WORKDIR/root/etc/shadow")
[[ "$debug_shadow" == '!'* && "$root_shadow" == '!'* ]]

umount "$WORKDIR/root/mnt"
umount "$WORKDIR/root/run"
umount -l "$WORKDIR/root/proc"
umount -l "$WORKDIR/root/sys"
umount -l "$WORKDIR/root/dev"
umount "$WORKDIR/root"
e2fsck -fn "$ROOT_PART" 2>&1 | tee "$WORKDIR/e2fsck.log" || status=$?
status=${status:-0}
(( status < 4 ))
losetup -d "$LOOPDEV"
LOOPDEV=

echo "verification passed: $IMAGE"
