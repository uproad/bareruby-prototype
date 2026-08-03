# Build, flash, and run STM32 firmware

Complete [setup.md](setup.md) first. The commands below assume that the ARM toolchain,
the STM32Cube HAL and a CubeMX project are under `.tools/stm32cube/`.

The examples use these directories:

```text
/home/user/bareruby/bareruby-prototype
/home/user/bareruby/bareruby-prototype/.tools/stm32cube/F446_Sample
```

Replace them with the paths used on the local machine.

## Build a sample

```sh
cd /home/user/bareruby/bareruby-prototype
./bareruby build --target=f446 samples/heartbeat.rb --no-exceptions
```

The project is not named on the command line. One Cube project under
`.tools/stm32cube/` is found without being named; a desk keeping several, or keeping one
elsewhere, says which in `target.yml`:

```yaml
    - machine: nucleo_f446re
      api: stm32cube
      triple: thumbv7em-none-eabihf
      options:
        configuration: Debug
        cube_project: /path/to/F446_Sample   # only when it is not the one under .tools/
```

A successful build says three things and nothing else:

```text
bareruby: synchronized generated sources into F446_Sample
bareruby: build (F446_Sample/Debug)
bareruby: firmware: build/nucleo_f446re-stm32cube-thumbv7em-none-eabihf/bareruby_program.elf
```

The compiler is chatty even when it succeeds, so its output is kept for the failure it
explains and shown only then.

`options.configuration` picks how the C and C++ are optimized: `Debug` builds with
`-Og -g3`, `Release` with `-O2`. Both leave the ELF in the same place.

Use `compile` instead of `build` to generate the C++ and stop before the toolchain runs:

```sh
./bareruby compile --target=f446 samples/heartbeat.rb --no-exceptions
```

Each build deletes and recreates `Core/Src/bareruby_*.cpp`, overwrites
`Core/Inc/bareruby_*.h`, and writes a `Makefile` in the Cube project. Ordinary CubeMX and
user files are not changed. The project must be writable. Nothing under `.tools/` is
committed here, so these generated files need no version control rules of their own.

## Flash with STM32CubeProgrammer

Connect the NUCLEO board and verify that ST-LINK is visible:

```sh
lsusb
```

Write, verify, and reset the ELF:

```sh
"$HOME/STMicroelectronics/STM32Cube/STM32CubeProgrammer/bin/STM32_Programmer_CLI" \
  -c port=SWD \
  -w build/nucleo_f446re-stm32cube-thumbv7em-none-eabihf/bareruby_program.elf \
  -v \
  -rst
```

The important success messages include `File download complete` and a successful
verification. The `-rst` option resets the MCU and starts the new firmware.

## Flash from STM32CubeIDE

A desk that has STM32CubeIDE can open or import the `F446_Sample` project in it, select a
Debug or Release configuration, create an STM32 C/C++ Application Run configuration using
ST-LINK over SWD, and run it. BareRuby-generated files are ordinary sources inside the
project, so the IDE builds and writes an equivalent ELF. Nothing here needs the IDE.

## Observe the program

For `heartbeat.rb`, LD2 turns on for 100 ms and off for 900 ms repeatedly. The sample
does not print serial messages.

Programs using `puts`, `UART.new(0, ...)`, or UART receive use USART2 through the
ST-LINK virtual COM port. Locate the device:

```sh
ls -l /dev/ttyACM*
```

Configure 115200 baud, 8N1 before reading it with `cat`:

```sh
stty -F /dev/ttyACM0 115200 cs8 -cstopb -parenb raw -echo
cat /dev/ttyACM0
```

`cat` alone does not configure the baud rate. A serial terminal can be used instead:

```sh
picocom -b 115200 /dev/ttyACM0
```

Exit picocom with `Ctrl+A`, followed by `Ctrl+X`.

## Troubleshooting

### `ruby: command not found`

Install Ruby 4 or prepend its `bin` directory to `PATH` as described in
[setup.md](setup.md).

### `no ARM toolchain at ...`

Unpack ARM's release under `.tools/` as the repository README describes, or name one that
is already installed:

```sh
export ARM_TOOLCHAIN_PATH=/path/to/arm-gnu-toolchain
```

### `no CubeIDE project under .tools/stm32cube`

Put a CubeMX project there, or name one as `options.cube_project` in `target.yml`. See
[setup.md](setup.md), which also covers starting from the NUCLEO template STM32CubeF4
ships when STM32CubeMX itself is not available.

### `main.c is not connected to BareRuby`

Add both `#include "bareruby_entry.h"` and `bareruby_entry();` to the CubeMX user
sections shown in [setup.md](setup.md).

### A HAL header is missing

`Drivers/` in an STM32CubeF4 checkout is a set of submodules. Initialize them as
[setup.md](setup.md) shows, then copy the HAL into the project.

### ST-LINK is not detected

On WSL2, run `usbipd list` in Windows and attach the ST-LINK device again. Then confirm
that `lsusb` in WSL reports an STMicroelectronics device. Also check the USB cable and
the ST-LINK jumpers on the NUCLEO board.

### `/dev/ttyACM0` is missing

Confirm that the complete ST-LINK USB device is attached to WSL, not only visible to
Windows. Reconnect it with usbipd and inspect `dmesg` and `lsusb`. The serial device is
needed only for UART communication, not for an SWD build.

### Serial output is unreadable

Configure the terminal for 115200 baud, 8 data bits, no parity, and one stop bit. Reset
the NUCLEO after opening the serial terminal so that startup messages are visible.
