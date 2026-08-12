# How a Raspberry Pi Pico is found on macOS, and why nothing here mounts anything.
#
# Sourced by flash.sh, which says what these six functions are for. Nothing here is run
# on its own.
#
# **The bootloader volume is already mounted before this file is reached.** macOS mounts
# a FAT volume the moment it arrives, so the whole privileged layer the Linux side needs
# — fstab, mount, sudo — is absent rather than replaced, and open_volume only has to say
# where the volume was put. That is not something its label can be asked: this macOS
# mounts an RP2040 bootloader on /Volumes/NO NAME, having not read the label at all.
#
# **ioreg is the only thing asked about hardware, and deliberately so.** diskutil and
# system_profiler both walk the device to answer, and a mass storage device that has
# stopped replying makes them hang rather than fail — which is exactly the state a board
# passes through every time it is written, since it reboots the instant the last block
# lands. ioreg reads the kernel's registry and returns whatever the state of the bus.

# 0x2e8a, in the decimal ioreg prints.
VENDOR=11914

# A board says which chip it is in its USB product id, and the bootrom and the firmware
# say it differently. Which of the two is running is not read from here — a board that
# presents a disk is in BOOTSEL and one that presents a callout device is running.
chip_of_usb_product() {
    case "$1" in
        3 | 10) echo rp2040 ;;
        15 | 9) echo rp2350 ;;
        *) echo unknown ;;
    esac
}

# One line per thing a Raspberry Pi USB device presents: SERIAL PRODUCT KIND NAME PORT.
#
# A device's own properties are printed before its children, so the serial and the
# product id standing above a BSD name are that name's — which is the whole of the
# lookup, and the reason this is one pass rather than a query per board. A hub's subtree
# holds the devices below it and each of those is matched in its own right, so every
# board is reached twice and the duplicates are dropped at the end.
#
# **The location id is where the board is plugged in.** It encodes the path through the
# hubs that reaches the device, so it is the same number before and after a reset into
# BOOTSEL, which the serial is not: an RP2040 reports the bootrom's id in the bootloader
# and the flash id once pico-sdk is running.
usb_nodes() {
    ioreg -c IOUSBHostDevice -r -l -w 0 | awk -v vendor="$VENDOR" '
        /"idVendor" = /          { device = $NF; next }
        /"idProduct" = /         { product = $NF; next }
        /"locationID" = /        { location = $NF; next }
        /"USB Serial Number" = / { serial = $NF; gsub(/"/, "", serial); next }
        device != vendor         { next }
        /"BSD Name" = /          { name = $NF; gsub(/"/, "", name); print serial, product, "disk", name, location; next }
        /"IOCalloutDevice" = /   { name = $NF; gsub(/"/, "", name); print serial, product, "tty", name, location; next }
    ' | sort -u
}

# One line per attached board: SERIAL CHIP STATE NODE PORT. A board in BOOTSEL is named
# by its partition, a running one by the serial port its firmware brought up, and both by
# where they are plugged in — the same answers the Linux side gives, so that flash.sh
# needs to know which system it is on only to source this file.
#
# The bootloader's disk is published under both its whole-disk name and its partition's,
# and the volume is on the first partition, so the whole disk is what is matched and the
# partition is named from it.
attached_boards() {
    local serial product kind name location chip counted
    usb_nodes | while read -r serial product kind name location; do
        chip=$(chip_of_usb_product "$product")
        [ "$chip" != unknown ] || continue
        case "$kind" in
            disk)
                counted=${name#disk}
                case "$counted" in "" | *[!0-9]*) continue ;; esac
                echo "$serial $chip bootsel /dev/${name}s1 $location"
                ;;
            tty) echo "$serial $chip running $name $location" ;;
        esac
    done
}

# Nothing to arrange. A bootloader volume arrives mounted and writable by whoever is
# logged in, so there is no privilege here to be given away in advance.
listing_advice() {
    :
}

# cu rather than tty: both name the same port, and cu is the one that opens without
# waiting for a carrier the bootloader will never raise.
reset_into_bootsel() {
    stty -f "$1" 1200 hupcl 2>/dev/null || true
}

reset_advice() {
    echo "       A bootloader volume macOS did not mount is not seen here either." >&2
}

# The kernel's own mount table, which costs nothing to read and cannot block on a device
# that has stopped answering. The mount point is taken whole because it can hold a
# space, which on this macOS it does.
mount_point_of() {
    local line
    line=$(mount | grep "^$1 on ") || return 1
    line=${line#"$1 on "}
    echo "${line% (*}"
}

# The disk is registered the moment the device is enumerated, and mounted a little after
# that by another process entirely, so a board found the instant it arrives — which is
# what a reset into BOOTSEL produces — has no mount point yet. Asking once loses that
# race and reads as "macOS did not mount it", so ask until it has.
wait_for_mount() {
    local attempt point
    for attempt in $(seq 20); do
        if point=$(mount_point_of "$1"); then
            echo "$point"
            return 0
        fi
        sleep 0.5
    done
    return 1
}

open_volume() {
    VOLUME=$(wait_for_mount "$1") || {
        echo "flash: macOS has not mounted $1, so there is nowhere to put the image." >&2
        exit 1
    }
    echo "flash: volume    $VOLUME"
}

# **Nothing is unmounted, because nothing can be.** The board reboots the moment the
# last block of the image lands, so the volume is gone before anything here could ask it
# to leave, and macOS reports that as a disk removed without being ejected. That notice
# is what a flash that worked looks like on this system; copying a .uf2 across by hand,
# which is how Raspberry Pi documents it, produces the same one.
close_volume() {
    :
}
