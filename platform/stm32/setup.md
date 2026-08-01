# STM32 environment setup

BareRuby does not include STM32Cube HAL, CMSIS, startup code, linker scripts, or a
generated STM32 project. Install STM32CubeIDE and prepare a user-owned CubeIDE project
before building STM32 firmware.

This guide describes the current NUCLEO-F446RE target on Ubuntu and WSL2.

## Required software

### Ruby 4

The BareRuby compiler uses Prism, which is included with Ruby 4. Install Ruby 4 and make
`ruby` available in `PATH`:

```sh
ruby --version
```

The verified compiler version is Ruby 4.0.3. If Ruby is installed in a private
directory, add its `bin` directory before running BareRuby:

```sh
export PATH=/path/to/ruby-4.0/bin:$PATH
```

### STM32CubeIDE for Linux

STM32CubeIDE is required for the final STM32 build. It supplies the ARM GNU toolchain,
the STM32-aware Eclipse builder, and `headless-build.sh`. Download the Linux installer
from STMicroelectronics, install it inside Ubuntu or WSL, and verify the headless
builder. For example:

```sh
test -x /opt/st/stm32cubeide_2.2.0/headless-build.sh
```

BareRuby searches `PATH` and `/opt/st/stm32cubeide_*` automatically. A nonstandard
installation can be selected explicitly:

```sh
export STM32CUBEIDE=/path/to/stm32cubeide/headless-build.sh
```

STM32CubeIDE 2.2.0 is the version verified by the current workflow. A separate system
ARM compiler is not required when CubeIDE is used.

### STM32CubeProgrammer or CubeIDE flashing support

Building only requires STM32CubeIDE. To write the resulting ELF from a terminal,
install STM32CubeProgrammer for Linux and locate its CLI:

```sh
test -x "$HOME/STMicroelectronics/STM32Cube/STM32CubeProgrammer/bin/STM32_Programmer_CLI"
```

Alternatively, open the external project in STM32CubeIDE and use its integrated
ST-LINK Run or Debug support.

## Prepare an external STM32 project

The STM32 project must live outside the BareRuby repository. Generate it with
STM32CubeIDE or a compatible STM32CubeMX release, then place or copy the complete
generated project into a user-owned directory. For example:

```text
/home/user/bareruby-stm32/F446_Sample
```

The directory must contain at least:

```text
F446_Sample/
├── .project
├── .cproject
├── F446_Sample.ioc
├── Core/
│   ├── Inc/
│   ├── Src/
│   └── Startup/
├── Drivers/
└── STM32F446RETX_FLASH.ld
```

Do not copy only the `.ioc` file for a normal build. BareRuby expects the generated HAL
sources, startup file, linker script, and CubeIDE metadata to be present as well.

### CubeMX configuration

Create an STM32CubeIDE project for the NUCLEO-F446RE and configure these resources:

- LD2 on PA5 as a GPIO output, with the generated names `LD2_GPIO_Port` and `LD2_Pin`.
- USART2 in asynchronous mode on PA2/PA3, with the generated handle `huart2`.
- USART2 at 115200 baud, 8 data bits, no parity, one stop bit, and no flow control.
- I2C1 on PB8/PB9, with the generated handle `hi2c1`, when using the I2C sample.
- Separate `.c` and `.h` generation for configured peripherals.
- STM32CubeIDE as the generated toolchain/project type.

The current I2C configuration uses no internal pull-ups. Connect external pull-up
resistors when using I2C1.

The project must compile C++ files. The current verified project uses the CubeIDE G++
compiler with these options:

```text
-std=gnu++14
-fno-exceptions
-fno-rtti
-fno-use-cxa-atexit
```

The BareRuby `--no-exceptions` option rejects unsupported Ruby exception constructs; it
does not edit the CubeIDE C++ compiler options.

### Connect CubeMX initialization to BareRuby

Add the BareRuby entry header inside `USER CODE BEGIN Includes` in
`Core/Src/main.c`:

```c
/* USER CODE BEGIN Includes */
#include "bareruby_entry.h"
/* USER CODE END Includes */
```

Call BareRuby after all generated `MX_*_Init` calls, inside `USER CODE BEGIN 2`:

```c
MX_GPIO_Init();
MX_USART2_UART_Init();
MX_I2C1_Init();

/* USER CODE BEGIN 2 */
bareruby_entry();
/* USER CODE END 2 */
```

Keep both edits in CubeMX user sections so that code regeneration preserves them.
`brd-stm32` checks these integration points before synchronizing generated files.

## Attach ST-LINK to WSL2

Native Ubuntu normally sees ST-LINK directly. Under WSL2, attach the USB device from an
administrator PowerShell terminal:

```powershell
usbipd list
usbipd bind --busid <BUSID>
usbipd attach --wsl --busid <BUSID> --auto-attach
```

Verify it inside WSL:

```sh
lsusb
```

A NUCLEO-F446RE commonly appears as:

```text
0483:374b STMicroelectronics ST-LINK/V2.1
```

For non-root serial access, add the Linux user to `dialout` and start a new login
session:

```sh
sudo usermod -aG dialout "$USER"
```

Continue with [build.md](build.md) after Ruby, STM32CubeIDE, the external project, and
ST-LINK are ready.
