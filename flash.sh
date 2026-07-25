#!/usr/bin/env bash
# Flash a .uf2 onto a Raspberry Pi Pico that is in BOOTSEL mode and attached to
# this WSL instance with usbipd. Defaults to the prototype's rp2040 artifact.
#
#     bareruby_prot/flash.sh [path/to/firmware.uf2]
#
# Needs root to mount the bootloader's mass storage device, so it re-executes
# itself under sudo when it is not already running as root.
set -euo pipefail

UF2="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/build/rp2040/build/bareruby_program.uf2}"
MOUNT_POINT=/mnt/pico

if [ ! -f "$UF2" ]; then
    echo "flash: no such file: $UF2" >&2
    exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
    exec sudo -- "$0" "$UF2"
fi

find_bootsel_partition() {
    local device name vendor model
    for device in /sys/block/sd*; do
        name=$(basename "$device")
        vendor=$(tr -d ' ' <"$device/device/vendor" 2>/dev/null || true)
        model=$(tr -d ' ' <"$device/device/model" 2>/dev/null || true)
        if [ "$vendor" = "RPI" ] && [ "$model" = "RP2" ]; then
            echo "/dev/${name}1"
            return 0
        fi
    done
    return 1
}

PARTITION=$(find_bootsel_partition) || {
    echo "flash: no RPI RP2 device found." >&2
    echo "       Hold BOOTSEL while plugging the Pico in, then attach it with usbipd." >&2
    exit 1
}

echo "flash: device    $PARTITION"
echo "flash: firmware  $UF2 ($(stat -c %s "$UF2") bytes)"

mkdir -p "$MOUNT_POINT"
mountpoint -q "$MOUNT_POINT" && umount "$MOUNT_POINT"
mount -t vfat -o rw,umask=000 "$PARTITION" "$MOUNT_POINT"

# The bootloader always exposes INFO_UF2.TXT. Refuse to write to anything else.
if [ ! -f "$MOUNT_POINT/INFO_UF2.TXT" ]; then
    umount "$MOUNT_POINT"
    echo "flash: $PARTITION is not an RP2 bootloader volume, aborting." >&2
    exit 1
fi
sed 's/^/flash: info      /' "$MOUNT_POINT/INFO_UF2.TXT"

# The Pico resets as soon as the last block lands, so the copy, the sync and the
# unmount are all expected to fail at the end. The device disappearing is the
# success signal.
cp "$UF2" "$MOUNT_POINT/" 2>/dev/null || true
sync 2>/dev/null || true
umount "$MOUNT_POINT" 2>/dev/null || true

for _ in $(seq 20); do
    if ! find_bootsel_partition >/dev/null; then
        echo "flash: done. The Pico left BOOTSEL mode and is running the firmware."
        exit 0
    fi
    sleep 0.5
done

echo "flash: the device is still in BOOTSEL mode. The firmware was not accepted." >&2
exit 1
