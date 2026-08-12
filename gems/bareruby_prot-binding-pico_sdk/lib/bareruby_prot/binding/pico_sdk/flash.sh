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
# than branches through one, and each answers the same six questions:
#
#     attached_boards            one line per board: SERIAL CHIP STATE NODE
#     listing_advice LINES       what --list should add here, given those lines
#     reset_into_bootsel NODE    reboot a running --debug firmware into the bootloader
#     reset_advice               what a reset that produced no board might mean here
#     open_volume NODE SER CHIP  set VOLUME to a directory the image can be copied into
#     close_volume               give VOLUME back, if it had to be taken
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

# Only boards carrying the image's chip are candidates, and --board narrows further.
candidates=$(attached_boards | awk -v chip="$CHIP" -v board="$BOARD" \
    '$2 == chip && (board == "" || $1 == board)')
count=$(printf '%s' "$candidates" | grep -c . || true)

if [ "$count" -eq 0 ]; then
    echo "flash: no attached board carries $CHIP." >&2
    echo "       Run '${BASH_SOURCE[0]} --list' to see what is attached." >&2
    echo "       A board running a default build shows nothing until BOOTSEL is held." >&2
    exit 1
fi

if [ "$count" -gt 1 ]; then
    echo "flash: $count boards carry $CHIP, so the image does not say which one to use." >&2
    echo "$candidates" | while read -r serial _ state node; do
        echo "         $serial   ($state, $node)" >&2
    done
    echo "       Put one serial under 'boards:' in that target's entry in config/target.yml." >&2
    echo "       Running this script by hand, --board SERIAL says it instead." >&2
    exit 1
fi

read -r SERIAL _ STATE NODE <<< "$candidates"
echo "flash: board     $SERIAL ($CHIP)"
# wc rather than stat, whose one flag for this is spelled differently on each system.
echo "flash: firmware  $UF2 ($(wc -c < "$UF2" | tr -d ' ') bytes)"

bootsel_nodes_of_chip() {
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
    BEFORE=$(bootsel_nodes_of_chip)
    echo "flash: $NODE is up, resetting it into BOOTSEL at 1200 baud"
    reset_into_bootsel "$NODE"
    PARTITION=""
    for _ in $(seq 40); do
        PARTITION=$(bootsel_nodes_of_chip | grep -vxF "${BEFORE:-$'\n'}" | head -1 || true)
        [ -n "$PARTITION" ] && break
        sleep 0.5
    done
    if [ -z "$PARTITION" ]; then
        echo "flash: no $CHIP board came back in BOOTSEL mode." >&2
        reset_advice
        exit 1
    fi
else
    PARTITION=$NODE
fi

echo "flash: device    $PARTITION"

open_volume "$PARTITION" "$SERIAL" "$CHIP"

# The bootloader always exposes INFO_UF2.TXT. Refuse to write to anything else.
if [ ! -f "$VOLUME/INFO_UF2.TXT" ]; then
    close_volume
    echo "flash: $PARTITION is not an RP2 bootloader volume, aborting." >&2
    exit 1
fi
sed 's/^/flash: info      /' "$VOLUME/INFO_UF2.TXT"

# The board resets as soon as the last block lands, so the copy, the sync and the
# unmount are all expected to fail at the end. The device disappearing is the
# success signal.
cp "$UF2" "$VOLUME/" 2>/dev/null || true
sync 2>/dev/null || true
close_volume

for _ in $(seq 20); do
    if ! bootsel_nodes_of_chip | grep -qxF "$PARTITION"; then
        echo "flash: done. The board left BOOTSEL mode and is running the firmware."
        exit 0
    fi
    sleep 0.5
done

echo "flash: $PARTITION is still in BOOTSEL mode. The firmware was not accepted." >&2
exit 1
