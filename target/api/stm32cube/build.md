# Build, flash, and run STM32 firmware

Complete [setup.md](setup.md) first. The commands below assume that STM32CubeIDE is
installed and that a complete CubeIDE project has been generated under
`.tools/stm32cube/`.

The examples use these directories:

```text
/home/user/bareruby/bareruby-prototype
/home/user/bareruby/bareruby-prototype/.tools/stm32cube/F446_Sample
```

Replace them with the paths used on the local machine.

## Build a sample

Change to the BareRuby repository and verify the required tools:

```sh
cd /home/user/bareruby/bareruby-prototype
ruby --version
test -x .tools/stm32cube/stm32cubeide_2.2.0/headless-build.sh
```

Build `heartbeat.rb` for the external project:

```sh
STM32_CUBE_PROJECT=.tools/stm32cube/F446_Sample \
STM32CUBEIDE=/opt/st/stm32cubeide_2.2.0/headless-build.sh \
./brd-stm32 samples/heartbeat.rb --no-exceptions
```

The project can also be supplied as a command-line option:

```sh
./brd-stm32 samples/heartbeat.rb \
  --cube-project=.tools/stm32cube/F446_Sample \
  --no-exceptions
```

The default configuration is `Debug`. A successful build ends with output similar to:

```text
Build Finished. 0 errors, 0 warnings.
brd-stm32: firmware: .tools/stm32cube/F446_Sample/Debug/F446_Sample.elf
```

Build a Release image with:

```sh
./brd-stm32 samples/heartbeat.rb \
  --cube-project=.tools/stm32cube/F446_Sample \
  --configuration=Release --no-exceptions
```

Use `--generate-only` to compile Ruby and synchronize the generated C++ without running
the CubeIDE builder:

```sh
./brd-stm32 samples/heartbeat.rb \
  --cube-project=.tools/stm32cube/F446_Sample \
  --no-exceptions --generate-only
```

Each run deletes and recreates `Core/Src/bareruby_*.cpp` and overwrites
`Core/Inc/bareruby_*.h` in the Cube project. Ordinary CubeMX and user files are not
changed. The project must be writable. Nothing under `.tools/` is committed here, so
these generated files need no version control rules of their own.

## Flash with STM32CubeProgrammer

Connect the NUCLEO board and verify that ST-LINK is visible:

```sh
lsusb
```

Write, verify, and reset the Debug ELF:

```sh
"$HOME/STMicroelectronics/STM32Cube/STM32CubeProgrammer/bin/STM32_Programmer_CLI" \
  -c port=SWD \
  -w .tools/stm32cube/F446_Sample/Debug/F446_Sample.elf \
  -v \
  -rst
```

The important success messages include `File download complete` and a successful
verification. The `-rst` option resets the MCU and starts the new firmware.

## Flash from STM32CubeIDE

Open or import the same `F446_Sample` project in STM32CubeIDE. Select its Debug
or Release configuration, create an STM32 C/C++ Application Run configuration using
ST-LINK over SWD, and run it. BareRuby-generated files are ordinary sources inside the
CubeIDE project, so the IDE writes the same ELF produced by the headless build.

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

### `STM32CubeIDE was not found`

Set the headless builder explicitly:

```sh
export STM32CUBEIDE=/opt/st/stm32cubeide_2.2.0/headless-build.sh
```

### `main.c is not connected to BareRuby`

Add both `#include "bareruby_entry.h"` and `bareruby_entry();` to the CubeMX user
sections shown in [setup.md](setup.md).

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
