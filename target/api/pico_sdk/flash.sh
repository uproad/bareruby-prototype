#!/usr/bin/env bash
# Flash a .uf2 onto one attached Raspberry Pi Pico board.
#
#     target/api/pico_sdk/flash.sh [--board SERIAL] [path/to/firmware.uf2]
#     target/api/pico_sdk/flash.sh --list
#
# Several boards can stay attached at once. Which one receives the firmware follows
# from the firmware itself: a .uf2 carries the family id of the chip it was built for,
# and only boards carrying that chip are considered. Two boards of the same chip — a
# Pico and a Pico W, a Pico 2 and a Pico 2 W — cannot be told apart that way, which is
# the whole reason a target is a board and not a chip. Name one of them with --board
# SERIAL; `--list` prints the serials.
#
# A board runs the firmware it was given, and a default build presents no USB interface
# at all, so it is invisible here until BOOTSEL is held. A --debug build stays visible
# and is reset into BOOTSEL over USB, with no button.
#
# Mounting the bootloader volume is the only step that needs privileges. Give /etc/fstab
# one line per board and the whole script runs as a normal user; `--list` prints the line
# to add. Without a line for the board the script re-executes itself under sudo.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)

# Where a board with no fstab line of its own gets mounted, under sudo.
FALLBACK_MOUNT_POINT=/mnt/pico

# The system mount is setuid root and honours the fstab "user" option. A mount from
# some other prefix on PATH (Homebrew's util-linux, say) is not setuid and cannot.
MOUNT=/usr/bin/mount
UMOUNT=/usr/bin/umount

BOARD=""
LIST=""
UF2=""
while [ $# -gt 0 ]; do
    case "$1" in
        --list) LIST=1 ;;
        --board) BOARD="$2"; shift ;;
        --board=*) BOARD="${1#--board=}" ;;
        *) UF2="$1" ;;
    esac
    shift
done

# The bootloader and the running firmware announce the same chip under different ids,
# and the flash id is the same in both, so a board keeps one identity across a reset.
chip_of_bootsel_model() {
    case "$1" in
        RP2) echo rp2040 ;;
        RP2350) echo rp2350 ;;
        *) echo unknown ;;
    esac
}

chip_of_usb_product() {
    case "$1" in
        000a) echo rp2040 ;;
        0009) echo rp2350 ;;
        *) echo unknown ;;
    esac
}

# The block device sits several levels below the USB device that carries the serial.
usb_directory_of() {
    local directory
    directory=$(readlink -f "$1")
    while [ ! -e "$directory/serial" ] && [ "$directory" != "/" ]; do
        directory=$(dirname "$directory")
    done
    [ -e "$directory/serial" ] && echo "$directory"
}

# One line per attached board: SERIAL CHIP STATE NODE. A board in BOOTSEL is named by
# its partition, a running one by the serial port its firmware brought up.
attached_boards() {
    local device model usb serial tty product
    for device in /sys/block/sd*; do
        [ -e "$device/device/vendor" ] || continue
        [ "$(tr -d ' ' < "$device/device/vendor")" = RPI ] || continue
        model=$(tr -d ' ' < "$device/device/model")
        usb=$(usb_directory_of "$device/device") || continue
        [ -n "$usb" ] || continue
        serial=$(cat "$usb/serial")
        echo "$serial $(chip_of_bootsel_model "$model") bootsel /dev/$(basename "$device")1"
    done
    for tty in /dev/ttyACM*; do
        [ -c "$tty" ] || continue
        usb=$(readlink -f "/sys/class/tty/$(basename "$tty")/device/..")
        # A board resetting into BOOTSEL can vanish mid-scan, so read defensively.
        [ "$(cat "$usb/idVendor" 2>/dev/null)" = 2e8a ] || continue
        product=$(cat "$usb/idProduct" 2>/dev/null) || continue
        serial=$(cat "$usb/serial" 2>/dev/null) || continue
        [ -n "$serial" ] || continue
        echo "$serial $(chip_of_usb_product "$product") running $tty"
    done
}

# The by-id path carries the serial, so it names one physical board even when two of
# them label their bootloader volume after the same chip.
fstab_line_for() {
    local serial=$1 chip=$2 model
    case "$chip" in
        rp2040) model=RP2 ;;
        rp2350) model=RP2350 ;;
        *) model=RP2 ;;
    esac
    echo "/dev/disk/by-id/usb-RPI_${model}_${serial}-0:0-part1 /mnt/pico-${serial:0:8} vfat noauto,user,umask=000 0 0"
}

if [ -n "$LIST" ]; then
    boards=$(attached_boards)
    if [ -z "$boards" ]; then
        echo "flash: no Raspberry Pi Pico board is attached."
        echo "       A board running a default (non --debug) build presents no USB interface;"
        echo "       hold BOOTSEL while plugging it in to see it here."
        exit 0
    fi
    printf '%-18s %-8s %-8s %s\n' SERIAL CHIP STATE DEVICE
    echo "$boards" | while read -r serial chip state node; do
        printf '%-18s %-8s %-8s %s\n' "$serial" "$chip" "$state" "$node"
    done
    echo
    echo "fstab lines (mount points may be renamed, but must be distinct):"
    echo "$boards" | while read -r serial chip state _; do
        if [ "$state" = bootsel ]; then
            echo "  $(fstab_line_for "$serial" "$chip")"
        else
            echo "  # $serial: put it in BOOTSEL and list again — the path holds the"
            echo "  #   bootrom's id, which an RP2040 does not report while running."
        fi
    done
    exit 0
fi

UF2="${UF2:-$HERE/build/pico-pico_sdk-thumbv6m-none-eabi/bareruby_program.uf2}"

if [ ! -f "$UF2" ]; then
    echo "flash: no such file: $UF2" >&2
    exit 1
fi

# Bytes 28..31 of a .uf2 are the family id, which is the chip the image was built for.
FAMILY=$(od -An -tx4 -j28 -N4 "$UF2" | tr -d ' ')
case "$FAMILY" in
    e48bff56) CHIP=rp2040 ;;
    e48bff57) CHIP=rp2350 ;;
    *)
        echo "flash: $UF2 carries family id 0x$FAMILY, which is not an RP2040 or RP2350 image." >&2
        exit 1
        ;;
esac

# Only boards carrying the image's chip are candidates, and --board narrows further.
candidates=$(attached_boards | awk -v chip="$CHIP" -v board="$BOARD" \
    '$2 == chip && (board == "" || $1 == board)')
count=$(printf '%s' "$candidates" | grep -c . || true)

if [ "$count" -eq 0 ]; then
    echo "flash: no attached board carries $CHIP." >&2
    echo "       Run 'target/api/pico_sdk/flash.sh --list' to see what is attached. A board running a" >&2
    echo "       default build shows nothing until BOOTSEL is held." >&2
    exit 1
fi

if [ "$count" -gt 1 ]; then
    echo "flash: $count boards carry $CHIP, so the image does not say which one to use." >&2
    echo "$candidates" | while read -r serial _ state node; do
        echo "         --board $serial   ($state, $node)" >&2
    done
    exit 1
fi

read -r SERIAL _ STATE NODE <<< "$candidates"
echo "flash: board     $SERIAL ($CHIP)"
echo "flash: firmware  $UF2 ($(stat -c %s "$UF2") bytes)"

bootsel_partitions_of_chip() {
    attached_boards | awk -v chip="$CHIP" '$2 == chip && $3 == "bootsel" { print $4 }'
}

# A firmware built with --debug keeps a USB CDC interface up, and pico-sdk reboots it
# into BOOTSEL when the port is opened at 1200 baud. That saves unplugging the board.
#
# The board cannot be followed across that reset by its serial: an RP2040 reports the
# bootrom's id in BOOTSEL and the flash id once pico-sdk is running, and the two are
# different numbers for the same board (an RP2350 happens to report one number for
# both). What identifies it instead is having appeared — the board in BOOTSEL that was
# not there a moment ago is the one just reset.
if [ "$STATE" = running ]; then
    BEFORE=$(bootsel_partitions_of_chip)
    echo "flash: $NODE is up, resetting it into BOOTSEL at 1200 baud"
    stty -F "$NODE" 1200 hupcl 2>/dev/null || true
    PARTITION=""
    for _ in $(seq 40); do
        PARTITION=$(bootsel_partitions_of_chip | grep -vxF "${BEFORE:-$'\n'}" | head -1 || true)
        [ -n "$PARTITION" ] && break
        sleep 0.5
    done
    if [ -z "$PARTITION" ]; then
        echo "flash: no $CHIP board came back in BOOTSEL mode." >&2
        echo "       After a reset the device re-enumerates, so usbipd may need to attach again" >&2
        echo "       ('usbipd attach --wsl --busid <id>' on the Windows side)." >&2
        exit 1
    fi
else
    PARTITION=$NODE
fi

echo "flash: device    $PARTITION"

# The block device appears before udev publishes /dev/disk, and the fstab lines name
# the volume through it, so resolving them the moment the board is found loses the race
# and looks like "this board has no line".
wait_for_disk_link() {
    local attempt link target
    target=$(readlink -f "$PARTITION")
    for attempt in $(seq 20); do
        for link in /dev/disk/by-id/* /dev/disk/by-label/*; do
            [ -e "$link" ] || continue
            [ "$(readlink -f "$link")" = "$target" ] && return 0
        done
        sleep 0.5
    done
    return 1
}

# Ask fstab where this board goes rather than assuming one place serves every board.
fstab_mount_point() {
    local device point target
    target=$(readlink -f "$PARTITION")
    while read -r device point _; do
        case "$device" in "" | \#*) continue ;; esac
        [ "$(readlink -f "$device" 2>/dev/null)" = "$target" ] || continue
        echo "$point"
        return 0
    done < /etc/fstab
    return 1
}

wait_for_disk_link || true
MOUNT_POINT=$FALLBACK_MOUNT_POINT
FSTAB_POINT=$(fstab_mount_point) && MOUNT_POINT=$FSTAB_POINT || FSTAB_POINT=""

echo "flash: mount     $MOUNT_POINT"
mountpoint -q "$MOUNT_POINT" && "$UMOUNT" "$MOUNT_POINT"

# udev creates the mount's device link a moment after the block device itself, so the
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

if [ -n "$FSTAB_POINT" ]; then
    mount_with_retry || {
        echo "flash: mounting $MOUNT_POINT through /etc/fstab failed." >&2
        exit 1
    }
else
    if [ "$(id -u)" -ne 0 ]; then
        echo "flash: no fstab line names $PARTITION, escalating"
        echo "       To keep this board out of sudo, add:"
        echo "         $(fstab_line_for "$SERIAL" "$CHIP")"
        exec sudo -- "$0" --board "$SERIAL" "$UF2"
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

# The board resets as soon as the last block lands, so the copy, the sync and the
# unmount are all expected to fail at the end. The device disappearing is the
# success signal.
cp "$UF2" "$MOUNT_POINT/" 2>/dev/null || true
sync 2>/dev/null || true
"$UMOUNT" "$MOUNT_POINT" 2>/dev/null || true

for _ in $(seq 20); do
    if ! bootsel_partitions_of_chip | grep -qxF "$PARTITION"; then
        echo "flash: done. The board left BOOTSEL mode and is running the firmware."
        exit 0
    fi
    sleep 0.5
done

echo "flash: $PARTITION is still in BOOTSEL mode. The firmware was not accepted." >&2
exit 1
