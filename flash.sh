#!/usr/bin/env bash
# Flash a .uf2 onto a Raspberry Pi Pico that is in BOOTSEL mode and attached to
# this WSL instance with usbipd. Defaults to the prototype's rp2040 artifact.
#
#     bareruby_prot/flash.sh [path/to/firmware.uf2]
#
# Mounting the bootloader volume is the only step that needs privileges. Give
# /etc/fstab this line once and the whole script runs as a normal user:
#
#     /dev/disk/by-label/RPI-RP2 /mnt/pico vfat noauto,user,umask=000 0 0
#
# Without it the script re-executes itself under sudo.
set -euo pipefail

UF2="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/build/rp2040/build/bareruby_program.uf2}"
MOUNT_POINT=/mnt/pico

# The system mount is setuid root and honours the fstab "user" option. A mount from
# some other prefix on PATH (Homebrew's util-linux, say) is not setuid and cannot.
MOUNT=/usr/bin/mount
UMOUNT=/usr/bin/umount

if [ ! -f "$UF2" ]; then
    echo "flash: no such file: $UF2" >&2
    exit 1
fi

find_bootsel_partition() {
    local device name vendor model
    for device in /sys/block/sd*; do
        name=$(basename "$device")
        # The device can vanish mid-scan once the board resets, so read defensively.
        vendor=$(cat "$device/device/vendor" 2>/dev/null | tr -d ' ')
        model=$(cat "$device/device/model" 2>/dev/null | tr -d ' ')
        if [ "$vendor" = "RPI" ] && [ "$model" = "RP2" ]; then
            echo "/dev/${name}1"
            return 0
        fi
    done
    return 1
}

wait_for_bootsel() {
    local attempt
    for attempt in $(seq 40); do
        if PARTITION=$(find_bootsel_partition); then
            return 0
        fi
        sleep 0.5
    done
    return 1
}

# A firmware built with --debug keeps a USB CDC interface up, and pico-sdk reboots it
# into BOOTSEL when the port is opened at 1200 baud. That saves unplugging the board.
reset_into_bootsel() {
    local port
    for port in /dev/ttyACM*; do
        [ -c "$port" ] || continue
        echo "flash: $port is up, resetting it into BOOTSEL at 1200 baud"
        stty -F "$port" 1200 hupcl 2>/dev/null || true
        return 0
    done
    return 1
}

if ! PARTITION=$(find_bootsel_partition); then
    if ! reset_into_bootsel || ! wait_for_bootsel; then
        echo "flash: no RPI RP2 device found." >&2
        echo "       Hold BOOTSEL while plugging the Pico in, then attach it with usbipd." >&2
        echo "       After a reset the device re-enumerates, so usbipd may need to attach again." >&2
        exit 1
    fi
fi

echo "flash: device    $PARTITION"
echo "flash: firmware  $UF2 ($(stat -c %s "$UF2") bytes)"

mountpoint -q "$MOUNT_POINT" && "$UMOUNT" "$MOUNT_POINT"

# udev creates /dev/disk/by-label a moment after the block device itself, so the
# first mount right after a reset can lose the race. Retry rather than give up.
mount_with_retry() {
    local attempt
    for attempt in $(seq 20); do
        if "$MOUNT" "$MOUNT_POINT" 2>/dev/null; then
            return 0
        fi
        sleep 0.5
    done
    return 1
}

if grep -qE "^[^#]*[[:space:]]$MOUNT_POINT[[:space:]]" /etc/fstab 2>/dev/null; then
    mount_with_retry || {
        echo "flash: mounting $MOUNT_POINT through /etc/fstab failed." >&2
        exit 1
    }
else
    if [ "$(id -u)" -ne 0 ]; then
        echo "flash: no fstab entry for $MOUNT_POINT, escalating"
        exec sudo -- "$0" "$UF2"
    fi
    mkdir -p "$MOUNT_POINT"
    "$MOUNT" -t vfat -o rw,umask=000 "$PARTITION" "$MOUNT_POINT"
fi

# The bootloader always exposes INFO_UF2.TXT. Refuse to write to anything else.
if [ ! -f "$MOUNT_POINT/INFO_UF2.TXT" ]; then
    "$UMOUNT" "$MOUNT_POINT"
    echo "flash: $PARTITION is not an RP2 bootloader volume, aborting." >&2
    exit 1
fi
sed 's/^/flash: info      /' "$MOUNT_POINT/INFO_UF2.TXT"

# The Pico resets as soon as the last block lands, so the copy, the sync and the
# unmount are all expected to fail at the end. The device disappearing is the
# success signal.
cp "$UF2" "$MOUNT_POINT/" 2>/dev/null || true
sync 2>/dev/null || true
"$UMOUNT" "$MOUNT_POINT" 2>/dev/null || true

for _ in $(seq 20); do
    if ! find_bootsel_partition >/dev/null; then
        echo "flash: done. The Pico left BOOTSEL mode and is running the firmware."
        exit 0
    fi
    sleep 0.5
done

echo "flash: the device is still in BOOTSEL mode. The firmware was not accepted." >&2
exit 1
