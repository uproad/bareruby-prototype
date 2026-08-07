# bareruby-prototype

BareRuby is a Ruby subset and an ahead-of-time compiler for microcontrollers. It
translates Ruby to C++ in a "better C" style, which a standard ARM toolchain plus the
target platform SDK or HAL turns into a native firmware image. There is no VM and no
garbage collector; every type is resolved at compile time.

**This repository is a throwaway feasibility prototype, not that compiler.** It exists to
answer one question by running it: can the pipeline the design calls for actually be
built end to end? It has no tests, no diagnostics and no error handling, and the only
command-line options are the few the build itself cannot do without. Happy path only, and
it is meant to be thrown away once it has answered the question.

The language specification and the real implementation live in separate repositories
that are not public yet. Nothing here points at them.

| File | What is in it |
| --- | --- |
| [`HISTORY.md`](HISTORY.md) | what each milestone proved, what it left out, and every size measured |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | how it is put together, and how to build, install and check a change |
| [`AGENTS.md`](AGENTS.md) | the rules an agent working here keeps to |

## Quick usage

```sh
$ ruby -v
ruby 4.0.3 ...                    # 4.0 or later

$ git clone https://github.com/uproad/bareruby-prototype
$ cd bareruby-prototype
$ ./bareruby new ../hello         # a project that builds without being edited
$ cd ../hello
$ $EDITOR Gemfile                 # uncomment connected board
$ bundle install
$ bin/bareruby target add         # it can offer that board now
$ bin/bareruby deploy             # compile, build, and write it onto the board
```

```ruby
Gemfile
  # if you have raspberry pi pico
  gem "bareruby_prot-binding-pico_sdk" # uncomment
```

**`deploy` writes over USB, so the board has to be visible from here.**

**Linux** — nothing to set up. Hold BOOTSEL while plugging the board in:

```sh
$ lsusb
... ID 2e8a:0003 Raspberry Pi RP2 Boot
```

**WSL** — Windows owns the device, and hands it over with
[usbipd-win](https://github.com/dorssel/usbipd-win). Install it once, in Windows:

```powershell
powershell
> winget install dorssel.usbipd-win
```

Then share the board, from an **elevated** PowerShell — `bind` is the step that needs it.
`usbipd list` also runs from WSL, as `usbipd.exe`, which is the quicker way to find a
BUSID:

```powershell
powershell
> usbipd list                        # while BOOTSEL is held, find the 2e8a:0003 line
> usbipd bind   --busid <BUSID>      # once per device. It stays shared afterwards
> usbipd attach --busid <BUSID> --wsl --auto-attach
```

```sh
wsl
$ lsusb                              # back in WSL
... ID 2e8a:0003 Raspberry Pi RP2 Boot
```

**Two things here are what a first attempt runs into.** The bootloader and the running
program are *different USB devices* — `2e8a:0003` and `2e8a:000a` on an RP2040,
`2e8a:000f` and `2e8a:0009` on an RP2350 — so run those three again once the board has
left BOOTSEL, and bind the second one too. And `--auto-attach` is not optional for a
board that stays plugged in: without it every reset drops the board out of WSL, and the
next flash stops at "no board came back in BOOTSEL mode", which is WSL plumbing rather
than the board. [More below](#flashing-a-pico), including mounting without
`sudo`.

**macOS** — nothing to set up, and one step less than Linux: the bootloader volume is
mounted before the flasher runs, so no `fstab` line and no `sudo` are involved. Hold
BOOTSEL while plugging the board in:

```sh
$ mount | grep msdos
/dev/disk4s1 on /Volumes/NO NAME (msdos, local, nodev, nosuid, noowners, noatime, fskit)
```

`NO NAME` rather than `RPI-RP2` because this macOS does not read the FAT label the
bootloader sets. Nothing depends on the name. [More below](#on-macos), including the one
thing not to ask macOS about.

`deploy` fetches the SDK and the cross compiler the first time it needs them. What every
verb does is [further down](#the-commands).

## What it has answered

The pipeline runs end to end, on real hardware, for three instruction sets — an RP2040
and an RP2350 through pico-sdk, a NUCLEO-F446RE through the STM32Cube HAL, and an
eight-bit ATmega2560 through the Arduino core. The language reaches M4, and the compiler
itself holds no peripheral and no board: bindings and standard classes arrive as gems, and
uninstalling one takes its machines away and leaves everything else compiling.

[`HISTORY.md`](HISTORY.md) records all of it, milestone by milestone, with the figures.

## The commands

`bareruby` is the only command. Its verbs stack: `build` compiles first, `deploy` builds
first, so each does its own work and then the next one's.

```sh
./bareruby new hello                         # a project that builds without being edited
./bareruby tools install                     # fetch what the recorded boards build with
./bareruby target add                        # once per board: answer a few questions
./bareruby deploy app.rb                     # compile, build, and write it onto them
./bareruby build app.rb --target=pico2       # one target, no flashing
./bareruby flash                             # write what the last build left, again
./bareruby compile app.rb                    # first stage only, no toolchain needed
./bareruby                                   # prints usage
```

| Verb | What it does | Reads `config/target.yml` |
| --- | --- | --- |
| `new` | writes a project: a Gemfile that lists the boards, a record holding this machine, and a program that blinks | no |
| `compile` | Ruby to C++, into `.bareruby/compile/<composition>/`. Makes no artifact, so `build/` stays empty | no — without `--target` the target is the machine doing the compiling |
| `build` | `compile`, then each binding's toolchain, leaving the artifact — and only that — in `build/<composition>/` | yes |
| `flash` | writes what `build` left onto the boards that take it | yes |
| `deploy` | `build`, then `flash` | yes |
| `target add` | asks which machine this is and writes it into `config/target.yml` | writes it |
| `target list` | every machine that can be targeted, by family | no |
| `tools install` | fetch what the recorded targets build with, pinned by version and hash | yes |
| `--version` | every gem an artifact was made from — the compiler, the bindings and the standard classes together decide the bytes on a board | no |
| `--help` | the usage, on output, with a status that says nothing went wrong | no |

`build` fetches what it needs itself, so `tools install` is only worth running on its own
when a step should be cached or seen in advance. `compile` fetches nothing at all: a desk
with not one SDK on it can still turn Ruby into C++.

**`build/` holds what was built, and nothing else** — one file per composition. Everything
else, the generated C++ and the tree a toolchain leaves behind, lives under `.bareruby/`.

A run says which stage each target is in and how long it has been there, redrawing the
table in place while it works. The stages are the verbs it stacked, so `deploy` has four
columns and `compile` has one:

```
$ bin/bareruby deploy
bareruby deploy app/main.rb · 3 targets
TARGET      TOOLS  COMPILE    BUILD    FLASH  ARTIFACT
pico1h       0.1s     0.1s     6.8s     9.9s  bareruby_program.uf2  70.5 KB
pico2w       0.1s     0.1s    7.2s+        .
mega2560     0.1s        .        .        .
deploy: 1/3 · 15.4s
```

A cell is `.` before its stage, seconds with a `+` while it runs, seconds when it is done,
and `FAIL` when the stage refused. Every artifact is at `build/<target>/`, so the row says
all of the path but the file name. The last line says how it went once it is over —
`deploy: success · 3/3 · 31.8s`, or `failed` where a target did not get through every
stage it was asked for. **How far along a stage is, is not asked** — cmake
counts translation units, and the link and the image that follow them are worth more than
any of them, so a proportion taken from that count reads 90% for as long as it reads
anything.

Anything else with something to say — a notice from a pass, a build system that refused,
the script naming the board it wrote — says it above the table, which keeps scrolling as
a log does. Where there is no terminal to redraw, in a pipe or in CI, there is no table:
each stage says one line as it finishes.

Three things go wrong, and the advice differs. Two are in the record:

```
config/target.yml names binding: pico_sdk, and no installed gem declares it.
Uncomment its line in the Gemfile and run `bundle install`.

config/target.yml: nothing is machine: pico, binding: pico_sdk, triple: thumbv7em-none-eabihf.
Run `bareruby target list`, or `bareruby target add` to be asked instead.
```

The third is on the command line — a `--target=` naming neither an entry nor a
composition. Both lists are handed back, because a name that reached here could have come
from either:

```
no target is named pico1x. config/target.yml records pico1h, pico2w, arduino_mega_2560.
`bareruby target list` prints every composition that can be named instead.
```

## A project of your own

`bareruby new hello` writes a project. **It builds without being edited**: the record it
comes with holds one entry — the machine doing the compiling, named `host` so that what it
builds is at `build/host/` on every desk — and `app/main.rb` blinks the onboard LED, which
on this machine is a stub that says on fd2 what it would have done.

```
hello/
├── .gitignore          build/, dump/, .tools/
├── Gemfile             what this is built from, and every board it could be built for
├── Gemfile.lock
├── README.md
├── bin/bareruby        the binstub. The entrance from here on
├── config/target.yml   which compositions this project is built for
└── app/main.rb         the program
```

```sh
./bareruby new hello
cd hello
bin/bareruby build                 # host. Unedited, and it runs
$EDITOR Gemfile                    # uncomment a board
bundle install
bin/bareruby target add            # it can offer that board now
bin/bareruby deploy
```

**The Gemfile is the catalogue.** Every board this ecosystem reaches is a line in it,
commented out, and uncommenting one is the whole cost of being able to build for that
board. `new` writes nothing into a directory that already holds any of the files it would
write; what is in the way is named, and the tree is left as it was.

## Recording which machines are here

`config/target.yml` says which compositions to build for. It is not tracked in this
checkout — which machines are at this desk is true of the desk — and it is not meant to be
written by hand: `./bareruby target add` asks, and writes the answer.

```
    - name:    (machine-pico_sdk-triple)
      machine: pending
      binding: pico_sdk
      triple:  pending
      debug:   pending
      boards:  []

  [›] machine  [ ] name  [ ] debug  [ ] confirm

  Which machine?

      family                machine

      none                  raspberry-pi-pico
      Arduino               raspberry-pi-pico-w
    › Raspberry Pi Pico     raspberry-pi-pico2
      ST NUCLEO             raspberry-pi-pico2-w

  ↑↓ move   →  machines   ^C cancel
```

Arrows move and Escape goes back; going back un-answers the question it lands on and
everything after it. Dim means one thing throughout — nobody has said this yet. What it
writes is an entry:

```yaml
bareruby:
  targets:
    - name: pico
      machine: pico
      binding: pico_sdk
      triple: thumbv6m-none-eabi
      debug: true
      boards: []
```

An empty name writes the composition; Tab fills in the machine's own name instead. The
name is the directory the artifacts land in, so one another entry already holds is
refused. **`boards:` is not asked for** — it is a serial read off the machine in front of
you, and it is not needed until two machines carrying one chip are attached at once, which
flashing detects and prints the candidates for.

**`debug:` is offered as `true`**, because a board is attached to be worked on and that is
the answer that hour needs: the firmware stays enumerated over USB, so the flasher resets
it over that port and the BOOTSEL button is not touched again. It costs roughly twice the
image, which is what `false` is for once the program is finished rather than being written.
The question says so where it is asked, and says it only where it is true — the field
reaches the pico-sdk build and no other, so the Arduino core and a Cube project take it and
do nothing with it.

[`config/target.yml.sample`](config/target.yml.sample) documents every field.

## Targets

A target is a machine the artifacts are produced for. There are seven:

| Target | Short | Machine | Chip |
| --- | --- | --- | --- |
| `host` | — | the machine doing the compiling | — |
| `raspberry-pi-pico` | `pico` | Raspberry Pi Pico | RP2040 |
| `raspberry-pi-pico-w` | `picow` | Raspberry Pi Pico W | RP2040 |
| `raspberry-pi-pico2` | `pico2` | Raspberry Pi Pico 2 | RP2350 |
| `raspberry-pi-pico2-w` | `pico2w` | Raspberry Pi Pico 2 W | RP2350 |
| `stm32-nucleo-f446re` | `f446` | NUCLEO-F446RE | STM32F446RE |
| `arduino-mega2560` | `mega` | Arduino Mega 2560 | ATmega2560 |

The short names are for typing at a prompt; the full name is what the `build/` directory
and the manifest are named after either way. `--target=` is repeatable, so one run
produces artifacts for as many machines as it lists:

```sh
./bareruby compile                                            # ref.rb, for the host
./bareruby compile -d samples/blink.rb                        # debug firmware
./bareruby build --target=pico --target=pico2w samples/heartbeat.rb
./bareruby build --target=f446 --no-exceptions samples/heartbeat.rb
```

`bareruby compile` reads no configuration at all, and with nothing said the target is
`host`. From `build` onwards a command needs to know which desk it is standing at, and
that is what `target.yml` answers — so from there `--target=` takes a recorded entry's own
name as well, and looks for one before it looks for a composition. `compile` is the one
command that cannot, so a name only a desk knows is refused there rather than resolved.

Each target's directory under `build/` is named `<machine>-<binding>-<triple>`, which is
how much it takes to be unique — a Pico and a Pico W are both `thumbv6m-none-eabi` and
their firmware is not the same, and an RP2350 is built for Arm or for RISC-V:

```
build/none-host-x86_64-pc-linux/
build/pico-pico_sdk-thumbv6m-none-eabi/
build/pico2_w-pico_sdk-thumbv8m.main-none-eabihf/
build/nucleo_f446re-stm32cube-thumbv7em-none-eabihf/
build/mega2560-arduino-avr-none/
```

An entry in `target.yml` that gives a `name:` uses that instead, which is how one
composition can be built twice — a debug one and a release one — without the two landing
in one place. **That name is what `--target=` takes**, and it had to become so: naming the
composition reaches whichever entry spells it first, so the second one could be built and
could not be asked for. It is also the name `build/` is called after and the name the line
saying where the artifact went prints, so it is the name the next command is typed from.
Naming the composition still works, and still answers with the first entry spelling it.

## Two flags

`--no-exceptions` drops the exception mechanism: `begin` becomes a compile error and the
unwinder and its tables are left out. It is worth several kilobytes of flash even in a
program that never raises, and a great deal more in one that does — the figures are in
[`HISTORY.md`](HISTORY.md#what-exceptions-cost).

`-d` / `--debug` only affects the freestanding target. It turns on USB stdio, so `puts`
reaches a USB serial port instead of being dropped, and — the reason it exists — the board
**stays enumerated as a USB device while the program runs**, which is what lets it be
reflashed without the BOOTSEL button. It roughly doubles the image;
[`HISTORY.md`](HISTORY.md#what---debug-costs) has the numbers.

## What a build reaches for

`bareruby` fetches the SDKs and cross compilers itself, pinned by version and hash, into a
store that belongs to the desk rather than to a project. `BARERUBY_TOOLS` names it
somewhere else.

```text
~/.bareruby/tools/
├── common/arm/arm-gnu-toolchain-13.2.Rel1-x86_64-arm-none-eabi/
├── arduino/
│   ├── arduino-cli-1.5.2-rc.1/
│   ├── data/                           # the core: avr-gcc, avr-libc, avrdude
│   └── downloads/
└── pico_sdk/
    ├── pico-sdk-2.3.0/
    └── picotool-2.3.0/                 # the SDK fetches and builds this itself
```

`common/` is for what more than one binding reaches for: the Pico boards and the NUCLEO
are compiled by the same `arm-none-eabi-g++`.

Two of the SDK's submodules come with it and are needed for one thing each. **TinyUSB is
what `--debug` needs** — without it the SDK only warns and builds a firmware identical to
the non-debug one, so a `--debug` build silently is not one. **The CYW43 driver is what a
wireless board's on-board LED needs**, because that LED hangs off the radio.

**Not everything arrives as an archive to verify.** `arduino-cli` does, and is; the AVR
core does not — it is an index and a set of packages `arduino-cli` resolves for itself, so
there is no single file to hash and the version is pinned on its command line instead. The
command that owns a format is the one that fetches it, and both land on the same shelf
either way.

One binding is still not fetched this way. `stm32cube` installs itself with its own script,
into the project's `.tools/` rather than the desk's store, because what it puts there is
partly this project's — the CubeMX project a build is made against:

```text
.tools/stm32cube/
├── STM32CubeF4-1.28.3/                 # HAL, CMSIS, startup files, linker scripts
└── F446_Sample/                        # the CubeMX project this desk builds for
```

A desk that keeps its own copies elsewhere says so through the environment, and what is
set there wins: `PICO_SDK_PATH`, `PICO_TOOLCHAIN_PATH`, `PICOTOOL_FETCH_FROM_GIT_PATH`,
`ARM_TOOLCHAIN_PATH`, `ARDUINO_DIRECTORIES_DATA` and its two companions, and an
`arduino-cli` already on `PATH`. Toolchain output is shown only when a step fails.

What is not fetched is what the desk brings to any work at all: `ruby`, `make`, `cmake`,
`git`. Only Ruby is needed for the first stage — Prism ships with Ruby 4.0. Every run
rewrites `dump/`, `.bareruby/` and `build/`, none of which is tracked; `dump/` holds one
binary snapshot and one text dump per pass boundary, and the pipeline reloads each
representation from its own dump before the next pass.

## Per-target notes

### host

`fd1` is `puts` and `fd2` is the peripheral call trace. Needs a GNU `g++` 12 or newer;
Ubuntu 24.04 ships 13.3.

```sh
./bareruby build --target=host samples/features.rb
./build/none-host-x86_64-pc-linux/bareruby_program
```

`samples/blink.rb` loops forever by design — use `timeout 1`. Samples that receive take
their input on stdin: `printf 'ABCDhello UART\n' | ...` for `samples/uart_receive.rb`,
`printf 'OK' | ...` for `samples/i2c.rb`.

### NUCLEO-F446RE, through the STM32Cube HAL

The target needs a CubeMX project, which the desk generates for itself and keeps under
`.tools/stm32cube/`. CubeMX owns clocks, pins, HAL initialization, startup and the linker
script; the second stage hands the result to the same `arm-none-eabi-g++` the Pico boards
use, so STM32CubeIDE is not needed. One project under `.tools/` needs no naming; a desk
that keeps several says which:

```yaml
    - machine: nucleo_f446re
      binding: stm32cube
      triple: thumbv7em-none-eabihf
      options:
        configuration: Debug                 # -Og -g3, against -O2
        cube_project: /path/to/F446_Sample   # only when it is not the one under .tools/
```

The binding's [README](gems/bareruby_prot-binding-stm32cube/README.md) records project
preparation, the ownership boundary, CubeMX regeneration and pin mapping.

`./bareruby flash --target=f446` writes the ELF over SWD with `STM32_Programmer_CLI`,
naming ST-LINK probe serials from `boards:` when more than one probe is attached. **That
path has never been run** — the STM32 firmware verified so far was flashed by hand.

### Arduino Mega 2560, through arduino-cli

`--no-exceptions` is not optional here. The core compiles with `-fno-exceptions` and this
libc carries no unwinder, so a program containing `begin` has no build for this board
either way round.

Two things are needed and neither is asked for: `build` fetches `arduino-cli`, then has it
install the pinned core. 36 MB for the command and 325 MB for the core, onto the desk's
shelf rather than into the project, so the second project pays nothing.

```
bareruby: fetching arduino-cli-1.5.2-rc.1 into ~/.bareruby/tools
bareruby:   https://downloads.arduino.cc/arduino-cli/arduino-cli_1.5.2-rc.1_Linux_64bit.tar.gz
bareruby: fetching arduino:avr@1.8.8 into ~/.bareruby/tools
bareruby:   ~/.bareruby/tools/arduino/arduino-cli-1.5.2-rc.1/arduino-cli core install
```

A desk that has its own says so and nothing is fetched: an `arduino-cli` on `PATH` covers
the command, and `ARDUINO_DIRECTORIES_DATA` covers the core. Both are read before anything
reaches the network, so honouring them costs no download. What `bareruby` sets otherwise
keeps the core out of `~/.arduino15`, and it passes the same thing on every build.

`./bareruby flash --target=mega` writes the `.hex` over the serial port the board talks
on, found by asking `arduino-cli` which ports carry this board. `boards:` in `target.yml`
names a port only when two of the same board are attached. The board resets when the port
is opened, so a reader sees the program from its first line:

```sh
stty -F /dev/ttyACM2 115200 raw -echo
timeout 6 cat /dev/ttyACM2
```

There is no `--debug` here and nothing to turn on: the console is a bridge chip of the
board's own, so `puts` reaches it in every build.

## Flashing a Pico

`./bareruby deploy` builds and writes every board a run selected. **Which board a firmware
goes to follows from the firmware**: bytes 28..31 of a `.uf2` are the family id of the chip
it was built for, and only boards carrying that chip are considered. Boards can stay
attached together, which is what makes a Pico and a Pico 2 usable as one test bench.

Two boards of the *same* chip cannot be told apart that way. `boards:` in `target.yml`
says which one, and given nothing to go on the flasher refuses to guess:

```
flash: 2 boards carry rp2040, so the image does not say which one to use.
         --board E6625888179C592E   (running, /dev/ttyACM1)
         --board E0C9125B0D9B       (bootsel, /dev/sdf1)
```

**An RP2040 reports a different serial in BOOTSEL than while running** — the bootrom's id
against the flash id pico-sdk reads. Both are stable per board, but a board cannot be
followed across a reset by its serial. An RP2350 happens to report the same number in
both modes; do not rely on that.

`flash.sh --list`, in the pico-sdk binding's directory, prints what is attached with
serials, and on Linux the `/etc/fstab` line for each.

### From WSL

Windows owns the USB device until it is handed over, so a Pico in BOOTSEL mode does not
appear here on its own. From an **elevated** PowerShell — `bind` is the step that needs
it, while `usbipd list` also runs from WSL as `usbipd.exe`:

```powershell
usbipd list                                 # while BOOTSEL is held, find the 2e8a:0003 line
usbipd bind   --busid <BUSID>               # once per device. It stays shared afterwards
usbipd attach --busid <BUSID> --wsl --auto-attach
```

**The bootloader and the running program are different USB devices** — `2e8a:0003` and
`2e8a:000a` on an RP2040, `2e8a:000f` and `2e8a:0009` on an RP2350 — so bind the second
one too, once the board has left BOOTSEL. And **`--auto-attach` is not optional** for a
board that stays plugged in: without it every reset drops the board out of WSL, and the
next flash stops at "no board came back in BOOTSEL mode", which is WSL plumbing rather
than the board.

### On macOS

There is nothing to arrange. macOS mounts the bootloader volume as it arrives, so the
`fstab` line and the `sudo` re-exec below have no counterpart here — the flasher only has
to find where the volume was put, and reads that out of the kernel's mount table. It waits
for it, because the disk is registered as the device is enumerated and mounted a little
after that by another process, which a board arriving out of a reset would otherwise
outrun.

Two things are worth knowing. The volume is `/Volumes/NO NAME`, so the board is identified
through `ioreg` and the volume through its `INFO_UF2.TXT` rather than by name. And a
*Disk Not Ejected Properly* notice at the end of every flash is what success looks like:
the board reboots the instant the last block lands, so the volume cannot be handed back.
Copying a `.uf2` across by hand, which is how Raspberry Pi documents it, produces the same
notice.

**Do not ask `diskutil` or `system_profiler` about an attached board.** Both walk the
device to answer, so a mass storage device that has stopped replying makes them *hang*
rather than fail — an uninterruptible wait that `kill -9` does not end either. A board in
BOOTSEL can enter that state; unplug it and plug it back in with BOOTSEL held, which
releases whatever was waiting on it. `ioreg` reads the kernel's registry instead and
returns whatever the bus is doing, which is why it is the only thing the flasher asks.

### Without the BOOTSEL button

A firmware built with `-d` keeps its USB CDC interface up, and pico-sdk reboots the board
into BOOTSEL when that port is opened at 1200 baud. The flasher does this itself: with no
bootloader volume present it looks for the port the firmware brought up — `/dev/ttyACM*`
on Linux, `/dev/cu.usbmodem*` on macOS — resets it, waits for the board to come back as
mass storage, and writes. Edit, rebuild, rerun — no button, no replugging.

### Mounting without sudo, on Linux

Only the mount needs privileges. One line in `/etc/fstab` per board removes even that:

```
/dev/disk/by-id/usb-RPI_RP2_E0C9125B0D9B-0:0-part1    /mnt/pico  vfat noauto,user,umask=000 0 0
/dev/disk/by-id/usb-RPI_RP2350_34319CF054AB3BD6-0:0-part1 /mnt/pico2 vfat noauto,user,umask=000 0 0
```

`flash.sh --list` prints these lines for whatever is in BOOTSEL, serial and all. The mount
points are read back out of `/etc/fstab`, so they can be named anything as long as each is
distinct. Use the `by-id` path rather than `by-label`: two Pico 2 boards both label their
volume `RP2350`, and the link points at whichever udev saw last.

The `user` option lets any user mount that one entry and nothing else, which is much
narrower than a `NOPASSWD` sudoers rule; `/dev/ttyACM*` is already reachable through the
`dialout` group. Without a line for the attached board the script re-executes itself under
`sudo` and prints the line that would have avoided it. Two traps: the mount must be the
**setuid** `/usr/bin/mount`, since another `mount` first on `PATH` refuses with `must be
superuser to use mount`; and udev publishes the device link slightly after the block
device appears, so the script retries.

## The language, in brief

**Every object is a reference**, which is what Ruby does (`samples/object.rb`). `b = a`
names the object `a` names, a method is handed the caller's object and not a copy, and
only `dup` duplicates one. Storage belongs to the binding the creation expression was
assigned to — a local holds the instance on the stack, an instance variable holds it
inside the owning struct — and every other binding of that type is a pointer to it. The
variable-length string is the one whose storage no binding owns: the region owns it,
handle and bytes both, which is what lets a method create one and hand it back.

**`asleep` is the one call here that neither PicoRuby nor the mruby/c Common I/O guideline
defines.** `sleep` and `sleep_ms` wait from the moment they are called, so a loop's period
is its body plus the wait and it drifts by whatever the body costs. `asleep`, `asleep_ms`
and `asleep_us` wait from the moment the previous one returned instead, so the body comes
out of the wait and the loop holds its period. All three share one mark, counted in
microseconds since boot. A turn that overruns does not catch up. The name is provisional,
and the leading `a` means nothing at all.

The programs the milestones were verified with are in [`samples/`](samples/README.md),
which lists what each one covers. `ref.rb` stays at the root because it is what
`bareruby compile` compiles when it is given no argument.

## Versions this was verified against

| Tool | Version |
| --- | --- |
| Ruby | 4.0.3 |
| GNU g++ (hosted) | 13.3.0 |
| pico-sdk | 2.3.0 (both boards) |
| arm-none-eabi-g++ | 13.2.Rel1 (ARM official release) |
| cmake | 4.4.0 |
| arduino-cli | 1.5.2-rc.1 |
| arduino:avr core | 1.8.8 |
| avr-g++ | 7.3.0 (atmel3.6.1-arduino7) |
| STM32CubeMX project | 6.15.0, STM32CubeF4 HAL 1.28.3 |
| STM32CubeProgrammer | 2.23.0 |
| STM32CubeIDE | 2.2.0 (the STM32 hardware runs, and nothing since) |
| GNU Tools for STM32 | 14.3.1 (likewise) |

Which of these targets have actually run on a board, and which are built but never
flashed, is recorded in
[`HISTORY.md`](HISTORY.md#which-targets-have-actually-run).
