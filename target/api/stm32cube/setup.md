# STM32 environment setup

BareRuby tracks no STM32Cube HAL, CMSIS, startup code, linker script, or generated STM32
project: they are the desk's, and none of them is committed here. They are still kept
under `.tools/stm32cube/`, which is where everything a build reaches for is kept and
where nothing is committed from. Put an ARM toolchain, the STM32Cube HAL and a CubeMX
project there before building STM32 firmware.

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

### ARM GNU toolchain

The firmware is compiled and linked by `arm-none-eabi-g++` — the same toolchain the Pico
boards are built by, which is why it is filed under `common/` by instruction set rather
than under either API:

```sh
test -x .tools/common/arm/arm-gnu-toolchain-13.2.Rel1-x86_64-arm-none-eabi/bin/arm-none-eabi-g++
```

The repository README says how to install it. A compiler kept somewhere else is named:

```sh
export ARM_TOOLCHAIN_PATH=/path/to/arm-gnu-toolchain
```

**STM32CubeIDE is not required.** It is an Eclipse application that cannot be downloaded
without an ST account, and a firmware needs none of what it adds over the compiler: the
CubeMX project carries the linker script and the startup file, and the first stage writes
the makefile that compiles them together with the generated C++.

### STM32Cube HAL

The HAL, the CMSIS headers, the startup files and the linker scripts come from
STM32CubeF4, which is public and needs no account:

```sh
git clone --depth 1 -b v1.28.3 https://github.com/STMicroelectronics/STM32CubeF4.git \
  .tools/stm32cube/STM32CubeF4-1.28.3
git -C .tools/stm32cube/STM32CubeF4-1.28.3 submodule update --init --depth 1 \
  Drivers/CMSIS/Device/ST/STM32F4xx Drivers/STM32F4xx_HAL_Driver
```

`Drivers/` is a set of submodules there. Without that second command the checkout has the
project templates and no HAL to build them against.

### STM32CubeProgrammer, for flashing

Nothing above is needed to write the ELF onto a board; nothing here is needed to build
one. To flash from a terminal, install STM32CubeProgrammer for Linux and locate its CLI:

```sh
test -x "$HOME/STMicroelectronics/STM32Cube/STM32CubeProgrammer/bin/STM32_Programmer_CLI"
```

A desk that does have STM32CubeIDE can open the project in it and use its integrated
ST-LINK Run or Debug support instead.

## Prepare the STM32 project

Generate it with STM32CubeMX, then place or copy the complete generated project under
`.tools/stm32cube/`. For example:

```text
.tools/stm32cube/F446_Sample
```

One project there is found without being named. A desk keeping several, or keeping one
somewhere else, says which in `target.yml` as `options.cube_project`.

STM32CubeMX also needs an ST account. A desk without one can start from the NUCLEO
template STM32CubeF4 ships, which is a complete CubeIDE project — `.project`,
`.cproject`, `STM32F446RETX_FLASH.ld` — and carries the same startup file:

```sh
CUBE=.tools/stm32cube/STM32CubeF4-1.28.3
TEMPLATE=$CUBE/Projects/STM32446E-Nucleo/Templates
P=.tools/stm32cube/F446_Sample

mkdir -p $P/Core/Inc $P/Core/Src $P/Core/Startup
cp $TEMPLATE/Src/*.c $P/Core/Src/
cp $TEMPLATE/Inc/*.h $P/Core/Inc/
cp $TEMPLATE/STM32CubeIDE/.project $TEMPLATE/STM32CubeIDE/.cproject \
   $TEMPLATE/STM32CubeIDE/STM32F446RETX_FLASH.ld $P/
cp $CUBE/Drivers/CMSIS/Device/ST/STM32F4xx/Source/Templates/gcc/startup_stm32f446xx.s \
   $P/Core/Startup/
mkdir -p $P/Drivers/STM32F4xx_HAL_Driver $P/Drivers/CMSIS/Device/ST/STM32F4xx
cp -r $CUBE/Drivers/STM32F4xx_HAL_Driver/Inc $CUBE/Drivers/STM32F4xx_HAL_Driver/Src \
      $P/Drivers/STM32F4xx_HAL_Driver/
cp -r $CUBE/Drivers/CMSIS/Device/ST/STM32F4xx/Include $P/Drivers/CMSIS/Device/ST/STM32F4xx/
cp -r $CUBE/Drivers/CMSIS/Include $P/Drivers/CMSIS/
```

What the template does not carry is the part CubeMX would have generated from the pin and
peripheral configuration: `LD2_Pin` and `LD2_GPIO_Port` in `main.h`, `MX_GPIO_Init` in
`main.c`, and a `usart.c`/`usart.h` holding `huart2`, `MX_USART2_UART_Init` and
`HAL_UART_MspInit`. Those are written by hand, following the CubeMX configuration below —
about sixty lines, and the same sixty on any NUCLEO-F446RE. Rename the project in
`.project` while there, since the template calls itself `Templates`.

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

Configure these resources for the NUCLEO-F446RE:

- LD2 on PA5 as a GPIO output, with the generated names `LD2_GPIO_Port` and `LD2_Pin`.
- USART2 in asynchronous mode on PA2/PA3, with the generated handle `huart2`.
- USART2 at 115200 baud, 8 data bits, no parity, one stop bit, and no flow control.
- I2C1 on PB8/PB9, with the generated handle `hi2c1`, when using the I2C sample.
- Separate `.c` and `.h` generation for configured peripherals.
- STM32CubeIDE as the generated project type, which is what supplies the `.project`,
  the `.cproject` and the linker script. The IDE itself is not used to build.

The current I2C configuration uses no internal pull-ups. Connect external pull-up
resistors when using I2C1.

The generated units are C++, and the options they are compiled with are the first stage's
rather than the project's — it writes the makefile that builds them:

```text
-std=gnu++14
-fno-rtti
-fno-use-cxa-atexit
-fno-exceptions      # only under --no-exceptions
```

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

Keep both edits in CubeMX user sections so that code regeneration preserves them. The
second stage checks these integration points before synchronizing generated files.

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

Continue with [build.md](build.md) after Ruby, the ARM toolchain, the HAL, the Cube
project, and ST-LINK are ready.
