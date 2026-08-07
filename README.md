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
that are not public yet. Nothing here points at them. Comments record why a decision was
made in their own terms, so this repository reads on its own.

This file is what a person needs to run it. Three others carry the rest:

| File | What is in it |
| --- | --- |
| [`HISTORY.md`](HISTORY.md) | what each milestone proved, what it deliberately left out, and every size and timing measured while proving it |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | how the thing is put together — the gems, the bindings, the passes — and how to build, install and check a change |
| [`AGENTS.md`](AGENTS.md) | the rules an agent working in this repository keeps to |

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
than the board. [More below](#flashing-a-pico-from-wsl), including mounting without
`sudo`.

**macOS** — untried. `flash.sh` reads `/sys`, so flashing a Pico is Linux-only; `compile`
and `build` reach for neither.

`deploy` fetches the SDK and the cross compiler the first time it needs them. What every
verb does is [further down](#the-short-way).

## What it has answered

The pipeline runs end to end, on real hardware, for three instruction sets. Ruby reaches
C++ through eight to twelve passes; a standard toolchain and a platform SDK turn that into
a firmware image; the image blinks a board.

- **The language** — M0 through M4: control flow, strings, keyword arguments, symbols,
  `Fixed`, inheritance and modules flattened while compiling, fixed-capacity arrays, an
  arena with a growing array and a variable-length string in it, nilable values, and
  experimental GPIO interrupts.
- **The machines** — a Raspberry Pi Pico and a Pico 2 W through pico-sdk, a
  NUCLEO-F446RE through the STM32Cube HAL, and an Arduino Mega 2560 through the Arduino
  core. The last of those is eight-bit, and it found three faults every 32-bit target had
  been agreeing with.
- **The shape** — the compiler holds no peripheral and no board. Bindings and standard
  classes arrive as gems, and uninstalling one takes its machines away and leaves
  everything else compiling.

[`HISTORY.md`](HISTORY.md) records all of it, milestone by milestone, with the figures.

## Two things worth knowing about the language

Every object is a reference, which is what Ruby does (`samples/object.rb`). `b = a` names
the object `a` names rather than a copy of it, a method is handed the caller's object and
not a copy — so what it changes, the caller sees — and a method that returns an object
returns that object. Only `dup` duplicates one. Storage belongs to the binding the
creation expression was assigned to: a local holds the instance on the stack, an instance
variable holds it inside the owning struct, and every other binding of that type is a
pointer to it. The array and the arena reached that rule first, one milestone at a time;
it holds for every object, peripherals included. The variable-length string is the one
whose storage no binding owns — the region owns it, handle and bytes both, which is what
lets a method create one and hand it back — and the rule that every binding names the same
string is unchanged by that.

`asleep` is the one call here that neither PicoRuby nor the mruby/c Common I/O guideline
defines. `sleep` and `sleep_ms` wait from the moment they are called — that is what
mruby/c and pico-sdk both do underneath — so a loop's period is its body plus the wait,
and it drifts by whatever the body costs. `asleep`, `asleep_ms` and `asleep_us` wait from
the moment the previous one returned instead, so the body comes out of the wait and the
loop holds its period. All three share one mark, counted in microseconds since boot; it
starts at boot and moves to each return. A turn that overruns does not catch up: it
returns at once and the missed time is gone. Holding the phase across an overrun, and
keeping more than one mark, are left out on purpose — a single mark serves one call per
loop, which is what these programs need. The name is provisional, and the leading `a`
means nothing at all.

## The sample programs

The programs the milestones were verified with are in [`samples/`](samples/README.md),
which lists what each one covers and records what the two ported programs had to change.
`ref.rb`, the representative program from the design documents, stays here at the root
because it is what `bareruby compile` compiles when it is given no argument.

## The short way

`bareruby` is the only command. Its verbs stack: `build` compiles first, `deploy` builds
first, so each does its own work and then the next one's.

```sh
./bareruby new hello                         # a project that builds without being edited

cd bareruby-prototype
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
| `--version` | which versions of these gems are here | no |
| `--help` | the usage, on output, with a status that says nothing went wrong | no |

**What made an artifact is not one version.** The compiler lowers the program, but a
binding's C++ is compiled into it and a standard class brings its own declarations and
translation units, so the bytes on a board are decided by all of them together — the same
reason a target is spelled out rather than named. `--version` lists every one of them.

Asking for the usage and getting it is not a misuse: `--help` puts it on output and exits
zero, while typing something that is not a command puts the same text on the error stream
and says so in the status.

**`build/` holds what was built, and nothing else.** One file per composition: the `.uf2`
for a Pico, the `.hex` for the Mega, the ELF for a NUCLEO, the executable for this machine.
Everything else — the generated C++, the build system that turns it into an artifact, the
tree a toolchain leaves behind — is *how* it was built, and lives under `.bareruby/`.

```text
build/                          .bareruby/compile/
└── pico1h/                     ├── bareruby_binding_*.cpp   the shared translation units
    └── bareruby_program.uf2    ├── bareruby_runtime_*.cpp
                                └── pico-pico_sdk-thumbv6m-none-eabi/
                                    ├── main.cpp  CMakeLists.txt  manifest.txt
                                    └── build/   what cmake left: 679 files, 9.4 MB
```

The numbers are why. A Pico composition was 11 MB across 684 files, of which the 52 KB
that goes on the board was one. `compile` now makes no `build/` at all, which is right:
it produces no artifact.

**Which of what a toolchain leaves is the artifact is the binding's answer**, and it was
already being given — every binding names one. Where artifacts go is this side's answer.
Neither had to learn anything about the other.

**A build says what it made.** Toolchains are quiet unless they fail, so without a line of
its own a first success is indistinguishable from nothing having happened — and there is no
other way to learn where the artifact went:

```
$ bin/bareruby build
bareruby: host -> build/host/bareruby_program
bareruby: raspberry-pi-pico -> build/pico-pico_sdk-thumbv6m-none-eabi/bareruby_program.uf2
```

**A refusal is one sentence, not a stack.** Being asked for a board nobody installed is not
a fault in this program: it knows exactly what is wrong and the person who typed the command
is the one who can fix it. Anything unplanned keeps its backtrace, because then the frames
are the report.

Two things go wrong with a record, in different places, and the advice differs:

```
config/target.yml names binding: pico_sdk, and no installed gem declares it.
Uncomment its line in the Gemfile and run `bundle install`.

config/target.yml: nothing is machine: pico, binding: pico_sdk, triple: thumbv7em-none-eabihf.
Run `bareruby target list`, or `bareruby target add` to be asked instead.
```

The first is the likely one — commenting a line back out, or cloning a project without
installing — and sending that person to `target add` would send them somewhere that cannot
help, since the command offers what is installed and this is not.

A third goes wrong on the command line rather than in the record, and it is the one this
program answered with a stack until recently — a `--target=` naming neither an entry nor a
composition:

```
no target is named pico1x. config/target.yml records pico1h, pico2w, arduino_mega_2560.
`bareruby target list` prints every composition that can be named instead.
```

Both lists are handed back because a name that reached here could have come from either.

`build` reaches for an SDK and a toolchain, and it fetches them itself. **The commands
stack, and `tools install` is at the bottom of the stack**: `build` fetches and then
compiles and then runs a toolchain, `deploy` builds and then flashes. Having its own verb
is what lets CI fetch in a step it can cache, and lets a desk see what is about to be
taken; having it underneath `build` is what makes a project someone cloned — its
`config/target.yml` already naming a Pico — build without anyone knowing it had to.

`compile` is the one command that does not stack it. The first stage reaches for no
toolchain at all, and a desk with not one SDK on it can still turn Ruby into C++.

```text
~/.bareruby/tools/
├── common/
│   └── arm/
│       └── arm-gnu-toolchain-13.2.Rel1-x86_64-arm-none-eabi/
└── pico_sdk/
    ├── pico-sdk-2.3.0/
    └── picotool-2.3.0/                 # the SDK fetches and builds this itself
```

**The store belongs to the desk, not to a project.** One pico-sdk serves every project on
a machine; keeping it under the checkout was right while there was only one checkout, and
`bareruby new` ended that. `BARERUBY_TOOLS` names it somewhere else. The version is in the
directory name because it is part of what a measurement means — moving from pico-sdk 1.5.1
to 2.3.0 changed every figure recorded below.

Only the Pico binding is fetched this way so far. `stm32cube` installs itself with its own
script, into the project's `.tools/`, from a lock of the same shape; `arduino` is not
fetched at all, because `arduino-cli` installs its own cores and there is no archive for
this side to bring down. Which of them has to be moved next is a question about those
bindings rather than about this mechanism.

```text
.tools/                                  # still project-local, for the two below
├── arduino/
│   ├── arduino-cli-1.5.2-rc.1/
│   ├── data/                           # the core: avr-gcc, avr-libc, avrdude
│   └── downloads/
└── stm32cube/
    ├── STM32CubeF4-1.28.3/             # HAL, CMSIS, startup files, linker scripts
    └── F446_Sample/                    # the CubeMX project this desk builds for
```

`common/` is for what more than one binding reaches for, filed under the instruction set it
serves rather than under a binding that only half-owns it: the Pico boards and the NUCLEO are
compiled by the same `arm-none-eabi-g++`, so it is neither `pico_sdk`'s nor `stm32cube`'s.
Its version is in its name for the same reason every other version here is.

A desk that keeps its own copies elsewhere says so through the environment, and what is
set there wins: `PICO_SDK_PATH`, `PICO_TOOLCHAIN_PATH`, `PICOTOOL_FETCH_FROM_GIT_PATH`,
`ARM_TOOLCHAIN_PATH`, `ARDUINO_DIRECTORIES_DATA` and its two companions, and an
`arduino-cli` already on `PATH`. Toolchain output is shown only when a step fails.

What is not here is what the desk brings to any work at all: `ruby`, `make`, `cmake`,
`git`. The line is what an artifact is made of — a cross compiler, an SDK, a board's
libraries — against what does the making.

The rest of this file is what `bareruby` does, step by step, and how to install what it
needs.

### Where a project starts

`bareruby new hello` writes a project. **It builds without being edited**: the record it
comes with holds one entry — the machine doing the compiling, named `host` so that what it
builds is at `build/host/` on every desk — and `app/main.rb` blinks the onboard LED, which
on this machine is a stub that says on fd2 what it would have done. So the first thing a
newcomer does succeeds, and it succeeds before any hardware has been bought.

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

`new` writes nothing into a directory that already holds any of the files it would write.
Those are the files a project is edited in — the program, the Gemfile the boards are
uncommented in, the record — and `new NAME` is easy to type a second time, out of shell
history or after a first attempt stopped partway. What is in the way is named, and the
tree is left exactly as it was.

**The Gemfile is the catalogue.** Every board this ecosystem reaches is a line in it,
commented out, and uncommenting one is the whole cost of being able to build for that
board. Nothing else holds that list, so there is no second copy to fall out of step —
which is also why the list is only ever read by a person. A command that read those
comment lines would be taking gem names apart, and a gem name is words rather than fields.
`target list` answers the neighbouring question, what is *installed*, and that answer comes
from the gems themselves.

```sh
./bareruby new hello
cd hello
bin/bareruby build                 # host. Unedited, and it runs
$EDITOR Gemfile                    # uncomment a board
bundle install
bin/bareruby target add            # it can offer that board now
bin/bareruby deploy
```

### Saying which machines are here

`config/target.yml` is not tracked *here*, because which machines are at this desk is true
of the desk rather than of this repository; in a project written by `./bareruby new` it is
tracked, because which compositions a project is built for is true of the project. It is
not meant to be written by hand either — `./bareruby target add` asks, and writes the
answer.

**What is on screen is the entry itself, in the words the file will use** — not a list of
questions that produces one afterwards, but the entry, being written:

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

Dim means one thing throughout — nobody has said this yet — whether it is a value the
cursor is resting on, a name being typed, or a field nothing has reached. Escape goes back
everywhere, which leaves the arrows to mean only movement, and going back un-answers the
question it lands on and everything after it: the screen says the same thing on the way
back as it does on the way in.

What it writes is an entry:

```yaml
bareruby:
  targets:
    - name: pico
      machine: pico
      binding: pico_sdk
      triple: thumbv6m-none-eabi
      debug: false
      boards: []
```

**Every field is written, whether or not it says anything.** Reading an entry tolerates a
missing `debug`, but that is a kindness to a file written by hand rather than a reason for
one written by a command to leave it out — an entry should read the same way to everyone
who opens it, without a default anybody has to already know.

An empty name writes the composition, which is long and unmistakable. Tab fills in the
machine's own name instead, which is short and what most people would have typed; when
that is taken, the binding is added if it tells the two apart and letters follow if it
does not — letters rather than numbers, because these machines are numbered and `pico_2`
sits one character away from a different board. A name another entry already holds is
refused: the name is the directory the artifacts land in.

**`boards:` is not asked for.** It is not knowable when an entry is made — a serial is
read off the machine in front of you, and an RP2040 answers with a different one in
BOOTSEL than while running — and it is not needed until two machines carrying one chip are
attached at once, which flashing detects and prints the candidates for. The field is
written empty, and filled in when that day comes.

[`config/target.yml.sample`](config/target.yml.sample) documents every field, for reading
a file back once it exists.

## Running the first stage

```sh
./bareruby compile                       # defaults to ref.rb
./bareruby compile samples/blink.rb
./bareruby compile -d samples/blink.rb   # debug firmware
```

### Choosing targets

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
and the manifest are named after either way, so nothing downstream has two spellings to
know about.

`--target=` names one and is repeatable, so a single run produces artifacts for as many
machines as it lists:

```sh
./bareruby compile --target=host samples/blink.rb
./bareruby compile --target=raspberry-pi-pico --target=raspberry-pi-pico2 samples/blink.rb
./bareruby compile --target=pico --target=picow --target=pico2 --target=pico2w samples/heartbeat.rb
./bareruby compile --target=f446 --no-exceptions samples/heartbeat.rb
```

`bareruby compile` reads no configuration at all: a compilation is exactly what its
command line asked for, and with nothing said the target is `host`. From `build` onwards a
command needs to know which desk it is standing at, and that is what `target.yml` answers —
and from there `--target=` takes an entry's own name too, for the reason
[below](#where-the-artifacts-land). This is the one command that cannot, so a name only a
desk knows is refused here rather than resolved.

### Where the artifacts land

A target's directory is the composition that made it:

```
build/none-host-x86_64-pc-linux/
build/pico-pico_sdk-thumbv6m-none-eabi/
build/pico_w-pico_sdk-thumbv6m-none-eabi/
build/pico2-pico_sdk-thumbv8m.main-none-eabihf/
build/pico2_w-pico_sdk-thumbv8m.main-none-eabihf/
build/nucleo_f446re-stm32cube-thumbv7em-none-eabihf/
build/mega2560-arduino-avr-none/
```

It is `<machine>-<binding>-<triple>`, and it is long because that is how much it takes to be
unique. The triple alone will not do: a Pico and a Pico W are both `thumbv6m-none-eabi` and
their firmware is not the same — one drives its LED from a pin and the other through the
radio, which brings a driver and a firmware blob with it. The board alone will not do
either, because an RP2350 is built for Arm or for RISC-V. What lies underneath is left out
of the name only because the triple already carries it. An entry in `target.yml` that gives
a `name:` uses that instead, which is how one composition can be built twice — a debug one
and a release one — without the two landing in one place.

**That name is what `--target=` takes**, and it had to become so: naming the composition
reaches whichever entry spells it first, so the second one could be built and could not be
asked for. From `build` onwards the option looks for a recorded name before a composition,
which is the order the two stand in front of the person typing — `build/` is named after
the entry, and the line saying where the artifact went prints that name, so it is the name
the next command is typed from. Naming the composition still works and still answers with
the first entry spelling it.

The entry `bareruby new` writes gives one for the other reason: **it is the only entry whose
directory would differ from desk to desk.** Its triple is whatever machine is doing the
compiling, so the path a project's own README would have to print is one no second desk can
use. Named `host`, the artifact is at `build/host/bareruby_program` for everybody, and that
is a path that can be typed and written down.

Only the selected targets are written. Their directories hold the generated entry point
and a `manifest.txt`; Pico targets also receive a `CMakeLists.txt`, the STM32 target a
`Makefile` and the exact source list synchronized into its Cube project, and the
Mega receives a sketch directory the reached translation units are gathered into. The runtime
and the bindings sit above them in `build/` and are shared. The Pico boards use the same
pico-sdk binding — the peripherals are reached through the SDK, which spells them the same
way whichever chip is underneath — and differ only in the two words their `CMakeLists.txt`
hands to it.

`--no-exceptions` drops the exception mechanism: `begin` becomes a compile error and the
unwinder and its tables are left out. It is worth several kilobytes of flash even in a
program that never raises, and a great deal more in one that does — the figures are in
[`HISTORY.md`](HISTORY.md#what-exceptions-cost).

`-d` / `--debug` only affects the freestanding target. It turns on USB stdio, so
`puts` reaches a USB serial port instead of being dropped, and — the reason it exists —
the board **stays enumerated as a USB device while the program runs**, which is what
lets `flash.sh` reflash it without the BOOTSEL button. It roughly doubles the image;
[`HISTORY.md`](HISTORY.md#what---debug-costs) has the numbers.

It needs the SDK's TinyUSB submodule. Without it the SDK builds a firmware identical to
the default one and says so only in a warning, so `--debug` looks like it worked and the
board never enumerates.

Only Ruby is needed for the first stage (Prism ships with Ruby 4.0). Every run rewrites
`dump/`, `.bareruby/` and `build/`, none of which is tracked in git — they are outputs,
and they changed on every commit while they were.

`dump/` holds one binary snapshot (`.bin`) and one inspector text dump (`.txt`) per pass
boundary. The pipeline reloads each representation from its own binary dump before handing
it to the next pass, so resumability and byte-level determinism are exercised on every run.

## Second stage: STM32Cube HAL

The NUCLEO-F446RE target uses a CubeMX project the desk generates for itself. CubeMX owns
clocks, pins, HAL initialization, startup and linker scripts; pass 12 supplies C++ through
the HAL.

That project is generated rather than downloaded, but a build reaches for it all the
same, so it is kept under `.tools/stm32cube/` with everything else a build reaches for.
One project there needs no naming. A desk that keeps several, or keeps its own somewhere
else, says which in `target.yml` — the same shape as an SDK path in the environment:

```yaml
    - machine: nucleo_f446re
      binding: stm32cube
      triple: thumbv7em-none-eabihf
      options:
        configuration: Debug
        cube_project: /path/to/F446_Sample   # only when it is not the one under .tools/
```

```sh
./bareruby build samples/heartbeat.rb --target=f446 --no-exceptions
```

CubeMX generates sources, not a build. The build it names is STM32CubeIDE — an Eclipse
application that cannot be downloaded without an ST account — and nothing in a firmware
needs it: the same sources, the same linker script and the same startup file, handed to
the `arm-none-eabi-g++` this repository already keeps for the Pico boards, produce the
image. So that is what the second stage does. The first stage writes the makefile that
says how, alongside the C++, the way it writes a `CMakeLists.txt` for a Pico.

The toolchain copies in only the translation units this program reached for, replaces
nothing but the files it owns, and brings the linked ELF back beside the
sources it was built from, so that flashing needs to know nothing about how the Cube
project arranges its output. `options.configuration` picks `-Og -g3` or
`-O2`; `ARM_TOOLCHAIN_PATH` names a compiler kept somewhere other than `.tools/`.
The binding's [README](gems/bareruby_prot-binding-stm32cube/README.md) records project preparation, the
ownership boundary, CubeMX regeneration, pin mapping, and supported bindings.

`./bareruby flash --target=f446` writes that ELF over SWD with `STM32_Programmer_CLI`,
naming ST-LINK probe serials from `boards:` when more than one probe is attached. **That
path has never been run** — the STM32 firmware verified so far was flashed by hand.

## Second stage: arduino-cli

The Mega 2560 is built by `arduino-cli`, which reads a sketch — a directory holding a
file of its own name, compiled whole. So the target's directory holds a
`bareruby_program/` the toolchain gathers into: the translation units the manifest names,
and the two headers, copied in beside a `bareruby_program.ino` that has nothing in it
because the program is in the `.cpp` next to it. The whole of it is one command:

```sh
./bareruby build samples/heartbeat.rb --target=mega --no-exceptions
```

`--no-exceptions` is not optional here. The core compiles with `-fno-exceptions` and this
libc carries no unwinder, so a program containing `begin` has no build for this board
either way round: with the flag the first stage rejects it, and without the flag the
second stage does.

Two things are needed, neither of them needing `sudo`.

```sh
mkdir -p .tools/arduino/arduino-cli-1.5.2-rc.1 && cd .tools/arduino/arduino-cli-1.5.2-rc.1
curl -fsSLO https://downloads.arduino.cc/arduino-cli/arduino-cli_1.5.2-rc.1_Linux_64bit.tar.gz
tar xf arduino-cli_1.5.2-rc.1_Linux_64bit.tar.gz
export ARDUINO_DIRECTORIES_DATA=$PWD/../data
./arduino-cli core install arduino:avr
```

That is 37 MB for the command and 381 MB for the core and the indexes it arrives with —
avr-gcc, avr-libc and avrdude among them, which is to say the compiler that actually
builds a sketch. Left alone `arduino-cli` files all of that under `~/.arduino15`, which
would put the larger half of this binding's toolchain outside the repository while the
command driving it sat inside; `ARDUINO_DIRECTORIES_DATA` says otherwise, and `bareruby`
passes the same thing on every build. `ARDUINO_DIRECTORIES_DOWNLOADS` and
`ARDUINO_DIRECTORIES_USER` follow it, so nothing is left in a home directory. None of
these carry a version, because `arduino-cli` keeps its own inside — one directory holds
every core and tool version it has been asked for.

What comes back is `bareruby_program.hex` and `bareruby_program.elf`, beside the sources
they were made from rather than under whatever name the tool gave them.

```sh
./bareruby flash --target=mega
```

writes the `.hex` over the same serial port the board talks on. There is no image to read
the chip out of and no volume to copy onto, so what identifies a board here is the port —
and rather than guess at one, `arduino-cli` is asked which ports carry the board this
firmware was built for. Three USB serial devices are attached to the desk this was
written on, two of them Picos; the right one is found and the other two are never
candidates. `boards:` in `target.yml` names a port only when two of the same board are
attached.

The board resets when the port is opened, so a serial reader sees the program from its
first line:

```sh
stty -F /dev/ttyACM2 115200 raw -echo
timeout 6 cat /dev/ttyACM2
```

There is no `--debug` here and nothing to turn on for output. The console is a bridge
chip of the board's own, always attached and always listening, so `puts` reaches it in
every build — where on a Pico stdout costs a USB stack and is off unless it is asked for.

## Second stage: hosted

Needs a GNU `g++` (version 12 or newer). Ubuntu 24.04 ships 13.3, which is fine.
The build command is recorded in the manifest, so just run what it says:

```sh
cd build/none-host-x86_64-pc-linux
g++ -std=gnu++20 -fno-rtti -I.. -o bareruby_program \
    main.cpp ../bareruby_binding_host.cpp ../bareruby_runtime_fixed.cpp \
    ../bareruby_runtime_stdio.cpp
./bareruby_program            # fd1 = puts, fd2 = peripheral call trace
```

The runtime is split across translation units by what each part costs to link, so the
source list varies with the program. Take it from `manifest.txt` rather than from here.

For `samples/uart_receive.rb`, stdin is the hosted UART wire:

```sh
printf 'ABCDhello UART\n' | ./bareruby_program
```

For `samples/i2c.rb`, stdin supplies the bytes returned by the hosted read:

```sh
printf 'OK' | ./bareruby_program
```

`samples/blink.rb` loops forever by design; use `timeout 1 ./bareruby_program` to look at
the head of the trace.

## Second stage: freestanding (`.uf2`)

Three tools are required. None of them need `sudo`.

### 1. pico-sdk

Use **2.3.0** for both boards. RP2350 support arrived in SDK 2.0.0 — 1.5.1 stops at
`rp2350.cmake does not exist` — and RP2040 is still supported there, so one checkout
serves both.

```sh
SDK=.tools/pico_sdk/pico-sdk-2.3.0
git clone -b 2.3.0 --depth 1 https://github.com/raspberrypi/pico-sdk.git $SDK
git -C $SDK submodule update --init --depth 1 lib/tinyusb lib/cyw43-driver
```

That is 33 MB for the SDK, 25 MB for TinyUSB and 10 MB for the CYW43 driver.
**The CYW43 driver is what a wireless board's on-board LED needs** — that LED hangs off
the radio, and the driver carries the firmware the radio runs. Without the submodule a
`raspberry-pi-pico-w` or `raspberry-pi-pico2-w` build that uses `OnboardLED` fails in
cmake; nothing else needs it.

**TinyUSB is what `--debug` needs**: it
turns on USB stdio, and without the submodule the SDK prints "TinyUSB submodule has not
been initialized; USB support will be unavailable" and builds a firmware byte-identical
to the non-debug one. Default builds disable both stdio channels and do not need it, so
the warning is harmless there — but a `--debug` build that silently is not one is worse
than a missing dependency, hence initializing it up front.

`picotool` needs no separate install: SDK 2.x downloads and builds it on demand. Left
alone it lands inside the target's build tree, which the next first-stage run deletes, so
`PICOTOOL_FETCH_FROM_GIT_PATH` points it somewhere outside — `bareruby` defaults that to
`.tools/pico_sdk/picotool-2.3.0` (17 MB, built once). Which picotool that is, is the SDK's
decision rather than this repository's, so it is filed under the SDK's version. Its
libusb-dependent parts are skipped when the headers are absent, which costs nothing here:
only `.uf2` generation is wanted.

Earlier work in this repository used **1.5.1**, which generates the `.uf2` with the
`elf2uf2` bundled in the SDK and so needs no picotool. That was the only reason to stay
on it, and it stopped being a reason once picotool was installed for the Pico 2. What
moving cost is recorded below.

### 2. ARM GNU toolchain

Download ARM's official release and unpack it. It bundles newlib, which is what
pico-sdk needs.

```sh
mkdir -p .tools/common/arm && cd .tools/common/arm
curl -fsSLO https://developer.arm.com/-/media/Files/downloads/gnu/13.2.rel1/binrel/arm-gnu-toolchain-13.2.rel1-x86_64-arm-none-eabi.tar.xz
tar xf arm-gnu-toolchain-13.2.rel1-x86_64-arm-none-eabi.tar.xz
```

This is the compiler the NUCLEO uses too, which is why it is under `common/arm/` rather
than under `pico_sdk/`.

Note the extracted directory capitalises the release differently from the tarball:
`arm-gnu-toolchain-13.2.Rel1-x86_64-arm-none-eabi`.

**Two Homebrew routes that do not work on Linux**, both verified here:

- `brew install arm-none-eabi-gcc` installs a bare cross compiler **without newlib**.
  There is no `libc.a` and no `nosys.specs`, and the pico-sdk build dies while linking
  `boot_stage2` with `cannot read spec file 'nosys.specs'`. There is no newlib formula
  in homebrew-core to pair with it.
- `brew install --cask gcc-arm-embedded` fails with `This cask requires macOS`. Casks
  are macOS-only; Linuxbrew cannot install them. The cask would have fetched exactly
  the ARM release downloaded above.

### 3. cmake

```sh
brew install cmake
```

Any recent cmake works; 4.4.0 was used here. The generated `CMakeLists.txt` declares
`cmake_minimum_required(VERSION 3.13)`, which cmake 4.x still accepts.

### Building the firmware

```sh
export PICO_SDK_PATH=$PWD/.tools/pico_sdk/pico-sdk-2.3.0
export PICO_TOOLCHAIN_PATH=$PWD/.tools/common/arm/arm-gnu-toolchain-13.2.Rel1-x86_64-arm-none-eabi
cd build/pico-pico_sdk-thumbv6m-none-eabi
cmake -B build -S .
cmake --build build
```

The result is `build/bareruby_program.uf2`. The `build/pico-pico_sdk-thumbv6m-none-eabi/build/` tree is
gitignored; `bareruby` deletes it on the next run along with the rest of `build/`.
`build/pico2-pico_sdk-thumbv8m.main-none-eabihf` is built by exactly the same commands with the same SDK — the
board's `CMakeLists.txt` carries the whole of the difference.

## Flashing a Pico from WSL

Windows owns the USB device until it is handed to WSL, so a Pico in BOOTSEL mode does
not appear here on its own. Attach it first, from an elevated Windows shell:

```powershell
usbipd list                    # find the bus id of "RP2 Boot"
usbipd bind   --busid <BUSID>  # once per device
usbipd attach --busid <BUSID> --wsl
```

The bootloader then shows up as a USB mass storage device — `2e8a:0003 Raspberry Pi
RP2 Boot` in `lsusb`, a removable 128 MiB disk in `dmesg`. Then run:

```sh
gems/bareruby_prot-binding-pico_sdk/lib/bareruby_prot/binding/pico_sdk/flash.sh --list                # what is attached, and the fstab line for each
gems/bareruby_prot-binding-pico_sdk/lib/bareruby_prot/binding/pico_sdk/flash.sh                       # defaults to the raspberry-pi-pico artifact
gems/bareruby_prot-binding-pico_sdk/lib/bareruby_prot/binding/pico_sdk/flash.sh path/to/other.uf2
gems/bareruby_prot-binding-pico_sdk/lib/bareruby_prot/binding/pico_sdk/flash.sh --board SERIAL path/to/other.uf2
```

The script locates boards by SCSI vendor `RPI` and by USB vendor `2e8a` rather than by a
fixed path, refuses to write unless the mounted volume carries the bootloader's
`INFO_UF2.TXT`, and treats the device disappearing as the success signal — the board
resets the moment the last block lands, so the copy, the sync and the unmount are all
expected to fail at the end.

### Several boards at once

Boards can stay attached together, which is what makes a Pico and a Pico 2 usable as one
test bench. **Which board a firmware goes to follows from the firmware**: bytes 28..31 of
a `.uf2` are the family id of the chip it was built for (`0xE48BFF56` for RP2040,
`0xE48BFF57` for RP2350), and only boards carrying that chip are considered. `deploy` uses
that to write every board a run selected, one after another:

```sh
./bareruby deploy samples/blink.rb          # every entry in target.yml
```

Two boards of the *same* chip — a Pico and a Pico W, a Pico 2 and a Pico 2 W — cannot be
told apart that way. That is not an oversight in the script; it is the same fact a
composition names a machine as well as a triple for. `boards:` in `target.yml` says which
one, and given nothing to go on `flash.sh` refuses to guess and prints the candidates:

```
flash: 2 boards carry rp2040, so the image does not say which one to use.
         --board E6625888179C592E   (running, /dev/ttyACM1)
         --board E0C9125B0D9B       (bootsel, /dev/sdf1)
```

`--list` shows the serials. One caveat found the hard way: **an RP2040 reports a
different serial in BOOTSEL than while running** — the bootrom's id (12 hex digits)
against the flash id pico-sdk reads (16 hex digits). They are both stable per board, but
they are different numbers, so a board cannot be followed across a reset by its serial.
An RP2350 happens to report the same number in both modes; do not rely on that. What
`flash.sh` follows across the reset instead is arrival: the board that is in BOOTSEL and
was not a moment earlier is the one it just reset.

### Reflashing without the BOOTSEL button

A firmware built with `-d` keeps its USB CDC interface up, and pico-sdk reboots the
board into BOOTSEL when that port is opened at 1200 baud. `flash.sh` does this itself:
if no bootloader volume is present it looks for a `/dev/ttyACM*`, resets it, waits for
the board to come back as mass storage, and flashes. Edit, rebuild, rerun `flash.sh` —
no button, no replugging.

usbipd sees BOOTSEL and the running program as two different devices, so **bind both of
them once**, and keep an auto-attach running so the flip between them is picked up:

```powershell
usbipd bind   --busid <BUSID>               # once while in BOOTSEL
usbipd bind   --busid <BUSID>               # once more while the program runs
usbipd attach --busid <BUSID> --wsl --auto-attach
```

The ids differ per chip: an RP2040 is `2e8a:0003` in BOOTSEL and `2e8a:000a` running, an
RP2350 `2e8a:000f` and `2e8a:0009`. **The auto-attach is not optional for a bench that
stays plugged in.** Without it every reset drops the board out of WSL and the next flash
stops at "no board came back in BOOTSEL mode" — which is a WSL plumbing failure, not a
board failure. One auto-attach per board.

### Mounting without sudo

Only the mount needs privileges. One line in `/etc/fstab` per board removes even that:

```
/dev/disk/by-id/usb-RPI_RP2_E0C9125B0D9B-0:0-part1    /mnt/pico  vfat noauto,user,umask=000 0 0
/dev/disk/by-id/usb-RPI_RP2350_34319CF054AB3BD6-0:0-part1 /mnt/pico2 vfat noauto,user,umask=000 0 0
```

`gems/bareruby_prot-binding-pico_sdk/lib/bareruby_prot/binding/pico_sdk/flash.sh --list` prints these lines for whatever is in BOOTSEL, serial and all. The
mount points are read back out of `/etc/fstab`, so they can be named anything as long as
each is distinct.

Naming boards by label instead — `/dev/disk/by-label/RPI-RP2`, `/dev/disk/by-label/RP2350`
— also works and is shorter, but only while one board of each chip is attached: two Pico 2
boards both label their volume `RP2350` and the link points at whichever udev saw last.
The `by-id` path carries the serial and stays unambiguous.

The `user` option lets any user mount that one entry, and nothing else — much narrower
than a `NOPASSWD` sudoers rule. `/dev/ttyACM*` is already reachable through the `dialout`
group, so with these entries `flash.sh` needs no root at all. Without a line for the
attached board, the script falls back to re-executing itself under `sudo` and prints the
line that would have avoided it.

Two traps worth knowing:

- The mount must be the **setuid** system binary. If another `mount` comes first on
  `PATH` (Homebrew's util-linux, for instance) it is not setuid and refuses with
  `must be superuser to use mount`. The script calls `/usr/bin/mount` explicitly.
- udev publishes `/dev/disk/by-label/RPI-RP2` slightly after the block device appears,
  so a mount issued immediately after a reset can lose the race. The script retries.

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

