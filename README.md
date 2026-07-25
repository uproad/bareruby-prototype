# bareruby_prot

Throwaway feasibility prototype for the BareRuby compiler. It exists to answer one
question by running it: **can the pipeline described in `docs/ARCHITECTURE.md` §3.4
actually be built?** It is not the implementation — that lives in `../bareruby`.

It has no tests, no diagnostics, no error handling and no CLI options. Happy path only.

Covered so far:

- **M0** — Prism → BRAST → TIR → LIR → C++ for the WP00 representative program
  (`ref.rb`), compiled with the host `g++` and executed.
- **M1** — the same eight passes produce an rp2040 firmware image for the blink
  program (`ref_blink.rb`), built with pico-sdk into a real `.uf2` and flashed onto a
  Raspberry Pi Pico, where it blinks.

## Running the first stage

```sh
ruby bareruby_prot/compile.rb                          # defaults to ref.rb
ruby bareruby_prot/compile.rb bareruby_prot/ref_blink.rb
ruby bareruby_prot/compile.rb -d bareruby_prot/ref_blink.rb   # debug firmware
```

`-d` / `--debug` only affects the freestanding target. It turns on USB stdio, so
`puts` reaches a USB serial port instead of being dropped, and — the reason it exists —
the board **stays enumerated as a USB device while the program runs**, which is what
lets `flash.sh` reflash it without the BOOTSEL button. It costs code size:

| | default | `--debug` |
| --- | --- | --- |
| `.uf2` | 17408 B | 45056 B |
| `text` (flash) | 8604 B | 22460 B |
| `bss` (RAM) | 1160 B | 3652 B |

Only Ruby is needed for this (Prism ships with Ruby 4.0). Every run rewrites two
directories:

- `dump/` — one binary snapshot (`.bin`) and one inspector text dump (`.txt`) per
  pass boundary. The pipeline reloads each representation from its own binary dump
  before handing it to the next pass, so resumability and byte-level determinism are
  exercised on every run.
- `build/` — the first-stage artifacts: the peripheral binding (declaration plus one
  implementation per target), the hosted runtime, and per-target `main.cpp`, build
  manifest and `CMakeLists.txt`. **`build/` is deleted and regenerated on every run.**

## Second stage: hosted

Needs a GNU `g++` (version 12 or newer). Ubuntu 24.04 ships 13.3, which is fine.
The build command is recorded in the manifest, so just run what it says:

```sh
cd bareruby_prot/build/hosted
g++ -std=gnu++20 -fno-rtti -I.. -o bareruby_program \
    main.cpp ../bareruby_binding_host.cpp ../bareruby_runtime_hosted.cpp
./bareruby_program            # fd1 = puts, fd2 = peripheral call trace
```

`ref_blink.rb` loops forever by design; use `timeout 1 ./bareruby_program` to look at
the head of the trace.

## Second stage: freestanding (rp2040, `.uf2`)

Three tools are required. None of them need `sudo`.

### 1. pico-sdk

Use **1.5.1**. That release generates the `.uf2` with the `elf2uf2` bundled in the SDK.
SDK 2.x moved `.uf2` generation out to `picotool`, which then has to be installed
separately — avoid that for now.

```sh
mkdir -p ~/pico
git clone -b 1.5.1 --depth 1 https://github.com/raspberrypi/pico-sdk.git ~/pico/pico-sdk
```

The TinyUSB submodule is not needed: both stdio channels are disabled in the generated
`CMakeLists.txt`, so the "TinyUSB submodule has not been initialized" warning during
configuration is expected and harmless.

### 2. ARM GNU toolchain

Download ARM's official release and unpack it. It bundles newlib, which is what
pico-sdk needs.

```sh
mkdir -p ~/toolchains && cd ~/toolchains
curl -fsSLO https://developer.arm.com/-/media/Files/downloads/gnu/13.2.rel1/binrel/arm-gnu-toolchain-13.2.rel1-x86_64-arm-none-eabi.tar.xz
tar xf arm-gnu-toolchain-13.2.rel1-x86_64-arm-none-eabi.tar.xz
```

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
cd bareruby_prot/build/rp2040
export PICO_SDK_PATH=$HOME/pico/pico-sdk
export PICO_TOOLCHAIN_PATH=$HOME/toolchains/arm-gnu-toolchain-13.2.Rel1-x86_64-arm-none-eabi
cmake -B build -S .
cmake --build build
```

The result is `build/bareruby_program.uf2`. The `build/rp2040/build/` tree is gitignored;
`compile.rb` deletes it on the next run along with the rest of `build/`.

Verified output for `ref_blink.rb`:

| Property | Value |
| --- | --- |
| `.uf2` size | 17408 bytes, 34 blocks |
| UF2 family id | `0xE48BFF56` (RP2040) |
| UF2 target address | `0x10000000` (XIP flash base) |
| `text` / `data` / `bss` | 8604 B / 0 B / 1160 B |

`arm-none-eabi-objdump -d bareruby_program.elf` shows the blink loop as Cortex-M0+
instructions, with `bareruby_main` inlined into `main` by the release build.

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
bareruby_prot/flash.sh                       # defaults to the rp2040 artifact
bareruby_prot/flash.sh path/to/other.uf2
```

The script locates the device by SCSI vendor `RPI` and model `RP2` rather than by a
fixed path, refuses to write unless the mounted volume carries the bootloader's
`INFO_UF2.TXT`, and treats the device disappearing as the success signal — the RP2040
resets the moment the last block lands, so the copy, the sync and the unmount are all
expected to fail at the end.

### Reflashing without the BOOTSEL button

A firmware built with `-d` keeps its USB CDC interface up, and pico-sdk reboots the
board into BOOTSEL when that port is opened at 1200 baud. `flash.sh` does this itself:
if no bootloader volume is present it looks for a `/dev/ttyACM*`, resets it, waits for
the board to come back as mass storage, and flashes. Edit, rebuild, rerun `flash.sh` —
no button, no replugging.

usbipd sees BOOTSEL (`2e8a:0003`) and the running program (`2e8a:000a`) as two
different devices, so **bind both of them once**, and keep an auto-attach running so
the flip between them is picked up:

```powershell
usbipd bind   --busid <BUSID>               # once while in BOOTSEL
usbipd bind   --busid <BUSID>               # once more while the program runs
usbipd attach --busid <BUSID> --wsl --auto-attach
```

### Mounting without sudo

Only the mount needs privileges. One line in `/etc/fstab` removes even that:

```
/dev/disk/by-label/RPI-RP2 /mnt/pico vfat noauto,user,umask=000 0 0
```

The `user` option lets any user mount that one entry, and nothing else — much narrower
than a `NOPASSWD` sudoers rule. `/dev/ttyACM*` is already reachable through the
`dialout` group, so with this entry `flash.sh` needs no root at all. Without it, the
script falls back to re-executing itself under `sudo`.

Two traps worth knowing:

- The mount must be the **setuid** system binary. If another `mount` comes first on
  `PATH` (Homebrew's util-linux, for instance) it is not setuid and refuses with
  `must be superuser to use mount`. The script calls `/usr/bin/mount` explicitly.
- udev publishes `/dev/disk/by-label/RPI-RP2` slightly after the block device appears,
  so a mount issued immediately after a reset can lose the race. The script retries.

Verified end to end on a Raspberry Pi Pico. With a default build, `2e8a:0003`
disappears from `lsusb` after flashing and GP25 (the on-board LED) blinks at the
500 ms period written in `ref_blink.rb`; the board presents no USB interface at all,
which is correct with both stdio channels disabled, and the button is needed to flash
again. With `-d` it comes back as `2e8a:000a` with a `/dev/ttyACM0`, and successive
edits were flashed by rerunning `flash.sh` alone — verified by changing the blink
period to 100 ms and then 800 ms and watching the LED follow.

## Versions this was verified against

| Tool | Version |
| --- | --- |
| Ruby | 4.0.3 |
| GNU g++ (hosted) | 13.3.0 |
| pico-sdk | 1.5.1 |
| arm-none-eabi-g++ | 13.2.Rel1 (ARM official release) |
| cmake | 4.4.0 |
