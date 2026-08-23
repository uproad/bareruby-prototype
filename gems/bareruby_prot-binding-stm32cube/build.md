# Build, flash, and run STM32 firmware

Complete [setup.md](setup.md) first — one `install.sh` run per desk.

## Build a sample

```sh
./bareruby build samples/heartbeat.rb --target=f446
```

`--target` takes the name this desk gave the entry in `config/target.yml` — the examples
here assume `f446`. Everything lands in `build/<that name>/`:

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

## Emulate

```sh
./bareruby emulate samples/string.rb --target=f446           # 3 virtual seconds
./bareruby emulate samples/heartbeat.rb --target=f446 --for=10
```

The ELF `build` leaves is run under [Renode](https://renode.io), headless, with no board
attached. The machine is written from the same manifests the firmware was built from —
memory sizes and the LED from the board and device YAML, the DWT counter at the proved
SYSCLK so a millisecond asked for is a virtual millisecond. What the board's stdout UART
said goes on screen and is kept LF-normalized at `.bareruby/emulate/<target>/uart.txt`,
so a test is one diff against the host build of the same program:

```sh
./bareruby build samples/string.rb --target=host --target=f446
./build/host/bareruby_program > expected.txt
./bareruby emulate samples/string.rb --target=f446
diff .bareruby/emulate/f446/uart.txt expected.txt
```

Virtual time makes the run deterministic: the same firmware leaves a byte-identical
`uart.txt` on every run and every desk, which is what lets CI hold the comparison.

Renode arrives with everything else `install.sh` pins — a 52 MB archive, 97 MB installed,
Linux x64 only, because that is the one platform upstream ships as a self-contained
archive. A desk that keeps
its own Renode names it with `RENODE`. The one thing the run fetches for itself is the
SVD file Renode reads register names from, once, into its own cache; the run works the
same without it.

What this does not prove: an emulated run is not a hardware run. The clock tree is
modeled as "already configured", I2C has no device behind it, and electrical reality —
pull-ups, timing margins, a wire — is not in the picture. `HISTORY.md` keeps the two
claims apart.

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
