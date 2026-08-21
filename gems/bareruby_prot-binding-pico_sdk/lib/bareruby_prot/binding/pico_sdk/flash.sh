#!/usr/bin/env bash
# Flash a .uf2 onto one attached Raspberry Pi Pico board.
#
#     flash.sh [--board SERIAL] path/to/firmware.uf2
#     flash.sh --list
#
# **This is shipped inside a gem, so where it is depends on the desk.** `bareruby deploy`
# runs it and never has to be told; run by hand, it is found with
#
#     bundle exec gem contents bareruby_prot-binding-pico_sdk | grep flash.sh
#
# and every line it prints about itself names the path it was actually run from.
#
# Several boards can stay attached at once. Which one receives the firmware follows
# from the firmware itself: a .uf2 carries the family id of the chip it was built for,
# and only boards carrying that chip are considered. Two boards of the same chip — a
# Pico and a Pico W, a Pico 2 and a Pico 2 W — cannot be told apart that way, which is
# the whole reason a target is a board and not a chip. Reached through `bareruby`, which
# has no --board of its own, the serial goes under `boards:` in the entry in
# config/target.yml; run by hand, --board says it. `--list` prints the serials either way,
# and so does the refusal when there is more than one candidate.
#
# A board runs the firmware it was given, and a default build presents no USB interface
# at all, so it is invisible here until BOOTSEL is held. A --debug build stays visible
# and is reset into BOOTSEL over USB, with no button.
#
# **Finding a board, and reaching the volume its bootloader presents, is the operating
# system's answer rather than this script's**, and the two systems differ by more than a
# flag: Linux publishes a block device and leaves the mounting to whoever wants it,
# while macOS has mounted it before anything here runs. So they are two files rather
# than branches through one, and each answers the same eight questions:
#
#     attached_boards            one line per board: SERIAL CHIP STATE NODE PORT
#     location_of PORT           where that board is, as this desk's own tools name it
#     firmware_of NODE PORT      what the firmware there declares itself to be
#     listing_advice LINES       what --list should add here, given those lines
#     reset_into_bootsel NODE    reboot a running --debug firmware into the bootloader
#     reset_advice               what a reset that produced no board might mean here
#     open_volume NODE SER CHIP  set VOLUME to a directory the image can be copied into
#     close_volume               give VOLUME back, if it had to be taken
#
# **PORT is the machinery's and LOCATION is the reader's**, and they are the same string
# on a desk whose boards are on its own bus. Everything here follows a board across a
# reset by its port, which is the kernel's and must not move; what somebody reads off a
# screen is whatever their own tools call the place — under WSL a board is not on a bus
# at all but a Windows device handed over by usbipd, named `7-1` there and in the command
# that hands it over, and telling them the kernel's number instead is telling them a
# number that appears nowhere they can act on.
#
# What is left in this file is what neither system gets a say in: which board the image
# is for, that the volume really is a bootloader, and the copy.
set -euo pipefail

BESIDE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

case "$(uname -s)" in
    Linux) source "$BESIDE/flash.linux.sh" ;;
    Darwin) source "$BESIDE/flash.darwin.sh" ;;
    *)
        echo "flash: no board is reached from $(uname -s)." >&2
        exit 1
        ;;
esac

BOARD=""
LIST=""
ATTACHED=""
RESET=""
DEVICE=""
UF2=""
while [ $# -gt 0 ]; do
    case "$1" in
        --list) LIST=1 ;;
        --attached) ATTACHED=1 ;;
        --reset) RESET="$2"; shift ;;
        --device) DEVICE="$2"; shift ;;
        --board) BOARD="$2"; shift ;;
        --board=*) BOARD="${1#--board=}" ;;
        *) UF2="$1" ;;
    esac
    shift
done

# **The three steps of writing a board, each reachable on its own.** Run by hand this
# script does all of them and needs to be told nothing but an image, which is what makes
# it usable without a project around it. A run writing several boards needs them apart:
# the boards are all reset, the bus is given time to settle, everything on it is looked at
# **once**, and only then is anything written — because a board looked for while others
# are re-enumerating is looked for at the worst possible moment, and on a transport that
# hands out its ports in arrival order it may not even be findable.
# What a board is, said in full: the five answers the machinery works from, and after them
# the two a person reads. They are asked for separately because they cost differently —
# a location may be a second file to open and a firmware name a second command to run —
# and nothing that merely writes a board should pay for either.
described() {
    local serial chip state node port
    while read -r serial chip state node port; do
        echo "$serial $chip $state $node $(location_of "$port")" \
             "$(firmware_of "$node" "$port")"
    done
}

if [ -n "$ATTACHED" ]; then
    attached_boards 2>/dev/null | described || true
    exit 0
fi

if [ -n "$RESET" ]; then
    reset_into_bootsel "$RESET"
    exit 0
fi

if [ -n "$LIST" ]; then
    boards=$(attached_boards 2>/dev/null || true)
    if [ -z "$boards" ]; then
        echo "flash: no Raspberry Pi Pico board is attached."
        echo "       A board running a default (non --debug) build presents no USB interface;"
        echo "       hold BOOTSEL while plugging it in to see it here."
        exit 0
    fi
    printf '%-18s %-8s %-8s %-14s %-10s %s\n' SERIAL CHIP STATE DEVICE LOCATION FIRMWARE
    echo "$boards" | described | while read -r serial chip state node location firmware; do
        printf '%-18s %-8s %-8s %-14s %-10s %s\n' \
            "$serial" "$chip" "$state" "$node" "$location" "$firmware"
    done
    listing_advice "$boards"
    exit 0
fi

# **There is no image to fall back on.** What was built is at build/<name>/ in whichever
# project asked for it, under the name that project's record gave the entry — which is
# exactly what a script shipped in a gem cannot know. It used to guess one, and the guess
# named a directory beside this file that has never existed on any desk.
if [ -z "$UF2" ]; then
    echo "flash: say which image to write." >&2
    echo "       ${BASH_SOURCE[0]} path/to/firmware.uf2" >&2
    echo "       \`bareruby deploy\` builds one and hands it over; by hand it is at" >&2
    echo "       build/<the entry's name>/bareruby_program.uf2 in the project." >&2
    exit 1
fi

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

# **Told which device, this asks nothing about which board.** That question was answered
# by whoever did the resetting, on a bus that had stopped moving, and asking it again here
# — one board at a time, while the others are being written — is asking it at the one
# moment it cannot be answered well.
if [ -n "$DEVICE" ]; then
    candidates=$(attached_boards 2>/dev/null | awk -v node="$DEVICE" '$4 == node' || true)
    if [ -z "$candidates" ]; then
        echo "flash: $DEVICE is not there any more." >&2
        exit 1
    fi
else
    # Only boards carrying the image's chip are candidates, and --board narrows further.
    candidates=$(attached_boards 2>/dev/null | awk -v chip="$CHIP" -v board="$BOARD" \
        '$2 == chip && (board == "" || $1 == board)' || true)
fi
count=$(printf '%s' "$candidates" | grep -c . || true)

if [ "$count" -eq 0 ]; then
    echo "flash: no attached board carries $CHIP." >&2
    echo "       Run '${BASH_SOURCE[0]} --list' to see what is attached." >&2
    echo "       A board running a default build shows nothing until BOOTSEL is held." >&2
    exit 1
fi

if [ "$count" -gt 1 ]; then
    echo "flash: $count boards carry $CHIP, so the image does not say which one to use." >&2
    echo "$candidates" | while read -r serial _ state node _; do
        echo "         $serial   ($state, $node)" >&2
    done
    echo "       Give each board the name of the entry it belongs to. That is one command a" >&2
    echo "       board, and it settles this for good:" >&2
    echo "         bareruby target attach --target=<the entry>" >&2
    echo "       Or put one serial under 'boards:' in that target's entry in config/target.yml." >&2
    echo "       Running this script by hand, --board SERIAL says it instead." >&2
    exit 1
fi

read -r SERIAL _ STATE NODE PORT <<< "$candidates"
echo "flash: board     $SERIAL ($CHIP)"
# wc rather than stat, whose one flag for this is spelled differently on each system.
echo "flash: firmware  $UF2 ($(wc -c < "$UF2" | tr -d ' ') bytes)"

# **A scan that finds nothing is an answer, and a scan that trips over a board leaving is
# the same answer.** These run while boards are rebooting — that is the whole of what they
# are for — so a device can disappear between the line that finds it and the line that
# reads it. Under `set -e` an empty answer and a stumble are the same to the caller only
# if this says so, and without that the script leaves with no status of its own and
# nothing said, which reads from outside as the flash having silently died.
bootsel_node_at_port() {
    attached_boards 2>/dev/null | awk -v port="$1" '$3 == "bootsel" && $5 == port { print $4 }' || true
}

# The board in BOOTSEL at a port, as the serial it answers to there and the partition it
# presents. **The serial is read again rather than carried across the reset**, because a
# bootloader does not answer to the one the firmware did.
# The board in BOOTSEL at a port, if it is the chip being written. **The chip is asked
# for as well as the port** because a port is not always the same board: where boards
# reach this desk over a network rather than off a bus — usbipd, handing a Windows device
# to WSL — two of them re-attaching at once can come back holding each other's port. A
# port that answers with the wrong chip is therefore not this board, and saying so is
# what keeps an image from following a number onto the wrong hardware.
bootsel_at_port() {
    attached_boards 2>/dev/null |
        awk -v port="$1" -v chip="$2" \
            '$3 == "bootsel" && $5 == port && $2 == chip { print $1, $4; exit }' || true
}

# Where the port has stopped answering for the board, the chip still does — as long as
# only one board of it arrived. Two boards of one chip reset together are genuinely
# indistinguishable once their ports have been shuffled, so that is refused rather than
# guessed at: guessing writes one board's program onto the other.
bootsel_of_chip_since() {
    local before=$1 chip=$2 arrived
    arrived=$(attached_boards 2>/dev/null |
        awk -v chip="$chip" '$3 == "bootsel" && $2 == chip { print $1, $4 }' |
        grep -vxF "${before:-$'\n'}" || true)
    [ "$(printf '%s' "$arrived" | grep -c . || true)" -eq 1 ] || return 0
    printf '%s' "$arrived"
}

# A firmware built with --debug keeps a USB CDC interface up, and pico-sdk reboots it
# into BOOTSEL when the port is opened at 1200 baud. That saves unplugging the board.
#
# **The board cannot be followed across that reset by its serial**: an RP2040 reports the
# bootrom's id in BOOTSEL and the flash id once pico-sdk is running, and the two are
# different numbers for the same board (an RP2350 happens to report one number for
# both). **What it does keep is the port it is plugged into**, so that is what it is
# followed by: the board that comes back in BOOTSEL at the port this one was at is this
# one.
#
# **A port is not always the same board either.** Off a bus it is: the socket does not
# move. Reached over usbipd, which hands a Windows device to WSL, two boards re-attaching
# at once have been seen to come back holding **each other's** port — measured, with each
# board then looked up under the other's identity. So the port is asked first and the
# chip is asked with it, and where that finds nothing the board is looked for by what
# arrived instead, which is the older question and the one a shuffled port cannot spoil.
# Two boards of one chip make that question ambiguous too, and it is then refused rather
# than answered wrongly.
if [ "$STATE" = running ]; then
    BEFORE=$(attached_boards 2>/dev/null |
        awk -v chip="$CHIP" '$3 == "bootsel" && $2 == chip { print $1, $4 }' || true)
    echo "flash: $NODE is up, resetting it into BOOTSEL at 1200 baud"
    reset_into_bootsel "$NODE"
    CAME_BACK=""
    for _ in $(seq 40); do
        CAME_BACK=$(bootsel_at_port "$PORT" "$CHIP")
        [ -z "$CAME_BACK" ] && CAME_BACK=$(bootsel_of_chip_since "$BEFORE" "$CHIP")
        [ -n "$CAME_BACK" ] && break
        sleep 0.5
    done
    if [ -z "$CAME_BACK" ]; then
        echo "flash: no $CHIP board came back in BOOTSEL mode at $PORT." >&2
        echo "       If more than one $CHIP board was written at once, their ports may have" >&2
        echo "       been shuffled as they re-attached, which leaves nothing to tell them" >&2
        echo "       apart. Writing them one at a time (--jobs=1) is the way through that." >&2
        reset_advice
        exit 1
    fi
    read -r BOOTSEL_SERIAL PARTITION <<< "$CAME_BACK"
else
    BOOTSEL_SERIAL=$SERIAL
    PARTITION=$NODE
fi

echo "flash: device    $PARTITION"

open_volume "$PARTITION" "$PORT"

# The bootloader always exposes INFO_UF2.TXT. Refuse to write to anything else.
if [ ! -f "$VOLUME/INFO_UF2.TXT" ]; then
    close_volume
    echo "flash: $PARTITION is not an RP2 bootloader volume, aborting." >&2
    exit 1
fi
sed 's/^/flash: info      /' "$VOLUME/INFO_UF2.TXT"

# **The volume says which chip it belongs to, so it is asked before anything is written.**
# Everything up to here identifies a board through the kernel and through udev, and those
# two are not published at the same instant; this is the board itself answering, on the
# volume about to be written. An image for one chip reaching another chip's bootloader is
# the failure this whole path exists to prevent, so it is checked rather than assumed.
#
# The Model line rather than the Board-ID: both systems present it, and it names the chip
# where Board-ID names the board (an RP2040 says `RPI-RP2` there, and a board that is not
# a Raspberry Pi one says whatever its maker chose).
case "$(sed -n 's/^Model: *Raspberry Pi *//p' "$VOLUME/INFO_UF2.TXT" | tr -d ' \r')" in
    RP2) FOUND=rp2040 ;;
    RP2350) FOUND=rp2350 ;;
    *) FOUND=unknown ;;
esac
if [ "$FOUND" != "$CHIP" ]; then
    close_volume
    echo "flash: $PARTITION presents a $FOUND bootloader and $UF2 is for $CHIP." >&2
    echo "       Nothing was written. Run '${BASH_SOURCE[0]} --list' to see what is attached." >&2
    exit 1
fi

# The board resets as soon as the last block lands, so the copy, the sync and the
# unmount are all expected to fail at the end. The device disappearing is the
# success signal.
cp "$UF2" "$VOLUME/" 2>/dev/null || true
sync 2>/dev/null || true
close_volume

gone=0
for _ in $(seq 24); do
    if ! bootsel_node_at_port "$PORT" | grep -qxF "$PARTITION"; then
        gone=$((gone + 1))
        if [ "$gone" -ge 4 ]; then
            echo "flash: done. The board left BOOTSEL mode and is running the firmware."
            exit 0
        fi
    else
        gone=0
    fi
    sleep 0.5
done

echo "flash: $PARTITION is still in BOOTSEL mode. The firmware was not accepted." >&2
exit 1
