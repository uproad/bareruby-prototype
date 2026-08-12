# How a Raspberry Pi Pico is found on Linux, and how its bootloader volume is taken.
#
# Sourced by flash.sh, which says what these six functions are for. Nothing here is run
# on its own.
#
# **Mounting is the only step that needs privileges**, and it is the reason this file is
# the longer of the two: the kernel publishes the volume and leaves mounting to whoever
# wants it. One line in /etc/fstab per board hands that back to a normal user, and
# without a line the script re-executes itself under sudo.

# Where a board with no fstab line of its own gets mounted, under sudo.
FALLBACK_MOUNT_POINT=/mnt/pico

# The system mount is setuid root and honours the fstab "user" option. A mount from
# some other prefix on PATH (Homebrew's util-linux, say) is not setuid and cannot.
MOUNT=/usr/bin/mount
UMOUNT=/usr/bin/umount

# The bootloader and the running firmware announce the same chip under different ids.
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

# One line per attached board: SERIAL CHIP STATE NODE PORT. A board in BOOTSEL is named
# by its partition, a running one by the serial port its firmware brought up.
#
# **PORT is where the board is plugged in, and it is the one thing that survives a
# reset.** The kernel names a USB device after the path through the hubs that reaches it
# — `1-2` is the second port of the first bus — and a board that reboots into its
# bootloader comes back on the same one. Its serial does not: an RP2040 reports the
# bootrom's id in BOOTSEL and the flash id once pico-sdk is running, and those are two
# different numbers for one board.
attached_boards() {
    local device model usb serial tty product
    for device in /sys/block/sd*; do
        [ -e "$device/device/vendor" ] || continue
        [ "$(tr -d ' ' < "$device/device/vendor")" = RPI ] || continue
        model=$(tr -d ' ' < "$device/device/model")
        usb=$(usb_directory_of "$device/device") || continue
        [ -n "$usb" ] || continue
        serial=$(cat "$usb/serial")
        echo "$serial $(chip_of_bootsel_model "$model") bootsel" \
             "/dev/$(basename "$device")1 $(basename "$usb")"
    done
    for tty in /dev/ttyACM*; do
        [ -c "$tty" ] || continue
        usb=$(readlink -f "/sys/class/tty/$(basename "$tty")/device/..")
        # A board resetting into BOOTSEL can vanish mid-scan, so read defensively.
        [ "$(cat "$usb/idVendor" 2>/dev/null)" = 2e8a ] || continue
        product=$(cat "$usb/idProduct" 2>/dev/null) || continue
        serial=$(cat "$usb/serial" 2>/dev/null) || continue
        [ -n "$serial" ] || continue
        echo "$serial $(chip_of_usb_product "$product") running $tty $(basename "$usb")"
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

# What --list adds here: the line that keeps this board out of sudo next time.
listing_advice() {
    echo
    echo "fstab lines (mount points may be renamed, but must be distinct):"
    echo "$1" | while read -r serial chip state _; do
        if [ "$state" = bootsel ]; then
            echo "  $(fstab_line_for "$serial" "$chip")"
        else
            echo "  # $serial: put it in BOOTSEL and list again — the path holds the"
            echo "  #   bootrom's id, which an RP2040 does not report while running."
        fi
    done
}

reset_into_bootsel() {
    stty -F "$1" 1200 hupcl 2>/dev/null || true
}

# Under WSL the board is Windows's until it is handed over, and a reset hands it back.
reset_advice() {
    echo "       After a reset the device re-enumerates, so usbipd may need to attach again" >&2
    echo "       ('usbipd attach --wsl --busid <id>' on the Windows side)." >&2
}

# The block device appears before udev publishes /dev/disk, and the fstab lines name
# the volume through it, so resolving them the moment the board is found loses the race
# and looks like "this board has no line".
wait_for_disk_link() {
    local attempt link target
    target=$(readlink -f "$1")
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
    target=$(readlink -f "$1")
    while read -r device point _; do
        case "$device" in "" | \#*) continue ;; esac
        [ "$(readlink -f "$device" 2>/dev/null)" = "$target" ] || continue
        echo "$point"
        return 0
    done < /etc/fstab
    return 1
}

# udev creates the mount's device link a moment after the block device itself, so the
# first mount right after a reset can lose the race. Retry rather than give up.
mount_with_retry() {
    local attempt
    for attempt in $(seq 20); do
        if "$MOUNT" "$1" 2>/dev/null; then
            return 0
        fi
        sleep 0.5
    done
    return 1
}

open_volume() {
    local partition=$1 serial=$2 chip=$3 fstab_point
    wait_for_disk_link "$partition" || true
    VOLUME=$FALLBACK_MOUNT_POINT
    fstab_point=$(fstab_mount_point "$partition") && VOLUME=$fstab_point || fstab_point=""

    echo "flash: mount     $VOLUME"
    mountpoint -q "$VOLUME" && "$UMOUNT" "$VOLUME"

    if [ -n "$fstab_point" ]; then
        mount_with_retry "$VOLUME" || {
            echo "flash: mounting $VOLUME through /etc/fstab failed." >&2
            exit 1
        }
    else
        if [ "$(id -u)" -ne 0 ]; then
            echo "flash: no fstab line names $partition, escalating"
            echo "       To keep this board out of sudo, add:"
            echo "         $(fstab_line_for "$serial" "$chip")"
            exec sudo -- "$0" --board "$serial" "$UF2"
        fi
        mkdir -p "$VOLUME"
        "$MOUNT" -t vfat -o rw,umask=000 "$partition" "$VOLUME"
    fi
}

close_volume() {
    "$UMOUNT" "$VOLUME" 2>/dev/null || true
}
