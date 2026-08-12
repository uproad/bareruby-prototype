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
        # A board is written by rebooting it, so one can vanish between any two lines of
        # this scan — including the scan run to find the one that just rebooted. Every
        # read is therefore allowed to fail into "not a board" rather than into an error.
        [ -e "$device/device/vendor" ] || continue
        [ "$(tr -d ' ' < "$device/device/vendor" 2>/dev/null)" = RPI ] || continue
        model=$(tr -d ' ' < "$device/device/model" 2>/dev/null) || continue
        usb=$(usb_directory_of "$device/device") || continue
        [ -n "$usb" ] || continue
        serial=$(cat "$usb/serial" 2>/dev/null) || continue
        [ -n "$serial" ] || continue
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

# **A volume is named by the port it arrived on, not by the board on it.** The by-id path
# carries the board's serial, and an RP2040's bootloader does not have one of its own:
# three boards measured on this desk — two of one model and one of another — all called
# themselves E0C9125B0D9B, down to the same model, revision and size. udev can publish one
# link for that name, so with three boards attached two of them had no by-id name at all,
# and a mount that followed the name reached whichever board happened to hold it. **Which
# is to say it wrote a board nobody asked for.**
#
# The by-path name is per port, and there is one of them for every device that is here.
# Identical boards no longer collide, because what is being named is where a board is
# rather than what it says it is.
#
# **Looked up rather than built.** The prefix belongs to the system — a PCI controller on
# one desk, a virtual host controller where the boards arrive over usbipd — so a name this
# side spelled out would match nothing. The kernel published it; this reads it back.
disk_link_for() {
    local partition=$1 target link
    target=$(readlink -f "$partition" 2>/dev/null) || return 1
    [ -n "$target" ] || return 1
    for link in /dev/disk/by-path/*; do
        [ -e "$link" ] || continue
        [ "$(readlink -f "$link" 2>/dev/null)" = "$target" ] || continue
        echo "$link"
        return 0
    done
    return 1
}

# **One line per port rather than one per board.** A desk says which of its sockets a
# board may be plugged into, and any board in one of them is then mountable — however many
# of them are identical, and whichever of them is there today.
fstab_line_for() {
    local link
    link=$(disk_link_for "$1") || return 0
    echo "$link /mnt/pico-$2 vfat noauto,user,umask=000 0 0"
}

# What --list adds here: the lines that keep these ports out of sudo next time.
listing_advice() {
    echo
    echo "fstab lines, one per port (mount points may be renamed, but must be distinct):"
    echo "$1" | while read -r _ _ state node port; do
        if [ "$state" = bootsel ]; then
            echo "  $(fstab_line_for "$node" "$port")"
        else
            echo "  # port $port: hold BOOTSEL and list again — a port is only named here"
            echo "  #   while a bootloader volume is on it."
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

# The block device appears before udev publishes /dev/disk, and the fstab lines name the
# volume through it, so resolving them the moment the board is found loses the race and
# looks like "this board has no line".
#
# **What is waited for is the link that names this board, pointing at this node.** Waiting
# for any link to point here is not the same question, and it is answered wrongly the
# moment two boards are written at once: the kernel reuses a node name as soon as the
# board that had it leaves, and the link udev published for that board still points there
# until udev catches up. A board then finds a link that resolves to its own node, follows
# it to an fstab line belonging to the board that left, and mounts the other board's
# volume. Naming the board asks about one board, and waiting until the answer is this
# node waits out udev rather than racing it.
wait_for_disk_link() {
    local partition=$1 attempt link
    for attempt in $(seq 40); do
        if link=$(disk_link_for "$partition"); then
            echo "$link"
            return 0
        fi
        sleep 0.5
    done
    return 1
}

# Ask fstab where this board goes rather than assuming one place serves every board.
#
# **The line is found by the path that names the board, spelled as written.** Resolving
# each line to a device and comparing nodes is the same question the block layer answers,
# and it answers it about now: a node that has just been handed to another board is still
# named by the link udev published for the board that left, so a resolving lookup can
# match a line belonging to a board that is no longer there. The by-id path carries the
# board's own serial, so comparing it as text asks about the board rather than about what
# is currently at a node. It is the path `--list` hands out, which is where these lines
# come from.
fstab_mount_point() {
    local wanted=$1 device point
    while read -r device point _; do
        case "$device" in "" | \#*) continue ;; esac
        [ "$device" = "$wanted" ] || continue
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
    local partition=$1 port=$2 link fstab_point
    link=$(wait_for_disk_link "$partition") || link=""
    VOLUME=$FALLBACK_MOUNT_POINT
    fstab_point=""
    if [ -n "$link" ]; then
        fstab_point=$(fstab_mount_point "$link") && VOLUME=$fstab_point || fstab_point=""
    fi

    echo "flash: mount     $VOLUME"
    mountpoint -q "$VOLUME" && "$UMOUNT" "$VOLUME"

    if [ -n "$fstab_point" ]; then
        mount_with_retry "$VOLUME" || {
            echo "flash: mounting $VOLUME through /etc/fstab failed." >&2
            exit 1
        }
    else
        if [ "$(id -u)" -ne 0 ]; then
            echo "flash: no fstab line names the port $partition is on"
            echo "       To keep this port out of sudo, add:"
            echo "         $(fstab_line_for "$partition" "$port")"
            # **Only where there is a terminal to ask for the password on.** A run writing
            # several boards gives each of them a pipe instead, so `sudo` would find
            # nowhere to print its prompt and nowhere to read the answer — and would wait
            # for that answer for as long as anybody let it, silently, because the prompt
            # it is waiting on was never seen. A refusal that says what to add is worth
            # more than a wait nobody can end.
            if [ ! -t 0 ] || [ ! -t 2 ]; then
                echo "flash: nothing here can ask for a password, so $partition is not mounted." >&2
                echo "       Add the line above to /etc/fstab, or run this flasher on its own" >&2
                echo "       in a terminal." >&2
                exit 1
            fi
            echo "flash: escalating"
            exec sudo -- "$0" --device "$partition" "$UF2"
        fi
        mkdir -p "$VOLUME"
        "$MOUNT" -t vfat -o rw,umask=000 "$partition" "$VOLUME"
    fi
}

close_volume() {
    "$UMOUNT" "$VOLUME" 2>/dev/null || true
}
