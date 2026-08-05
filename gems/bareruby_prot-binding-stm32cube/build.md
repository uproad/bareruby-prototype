# Build, flash, and run STM32 firmware

Complete [setup.md](setup.md) first — one `install.sh` run per desk.

## Build a sample

```sh
./bareruby build samples/heartbeat.rb --target=f446
```

`--target` takes the full name or the short form from `./bareruby target list`
(`f446`, `f401`, `f4disco`). Everything lands in `build/<composition>/`:

```text
bareruby_program.elf     the firmware
out/bareruby_program.map what the linker placed where
manifest.txt             what was built, from what, at which clock
bareruby_board.h/.c      the generated board adapter
bareruby_program.ld      the generated linker script
Makefile                 what the second stage ran
```

`-d`/`--debug` builds with `-Og -g3` instead of `-O2`. `--no-exceptions` leaves the
unwinder out. Use `compile` instead of `build` to generate the C++ and stop before the
toolchain runs.

The manifest answers most questions before they are asked:

```text
clock = hsi 16 MHz -> SYSCLK 84 MHz, AHB 84, APB1 42, APB2 84, 2 wait states
board_source = gem
stdout_channel = USART2
```

## Flash

```sh
./bareruby flash --target=f446      # what the last build left
./bareruby deploy samples/heartbeat.rb --target=f446   # build, then flash
```

Flashing runs the pinned OpenOCD against the board's ST-LINK: write, verify, reset.
With one probe attached nothing needs naming; with several, list the probe serials as
`boards:` in `config/target.yml` — SWD is reached through the probe, so it is the
probe's serial, not the board's.

## Serial

`puts` leaves by the board's stdout UART — the ST-LINK virtual COM port, 115200 8N1:

```sh
stty -F /dev/ttyACM0 115200 cs8 -cstopb -parenb raw -echo
cat /dev/ttyACM0
```

or `picocom -b 115200 /dev/ttyACM0` (exit: `Ctrl+A`, `Ctrl+X`). Reset the board after
opening the terminal so the first lines are visible.

## Troubleshooting

### `the pinned ARM toolchain is not at ...` / `the pinned stm32f4 SDK is not at ...`

Run the `install.sh` the message names, from the project root. A toolchain kept
elsewhere is named with `ARM_TOOLCHAIN_PATH`.

### `clock: ...` refusals at build

The board manifest's clock profile violates the device's limits — the message says
which figure and which bound. The profile is proved before any C is generated, so
nothing half-built remains.

### `... has no onboard LED, so OnboardLED cannot be built for it`

The board's manifest declares no `led:`. Wire one and declare it (a project-layer file
wins over the gem's), or reach a pin through `GPIO` instead.

### ST-LINK is not detected

On WSL2, attach the probe with `usbipd` from Windows and confirm `lsusb` reports an
STMicroelectronics device. Check the USB cable and the ST-LINK jumpers.

### `/dev/ttyACM0` is missing

The serial device is only needed for UART output, not for flashing. Reattach the
complete ST-LINK USB device to WSL and inspect `dmesg`.

### Serial output is unreadable

115200 baud, 8 data bits, no parity, one stop bit — and a reset after the terminal is
open.
