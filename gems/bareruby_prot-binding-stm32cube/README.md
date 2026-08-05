# STM32 platform

STM32 boards, built from this repository's own description of them. No STM32CubeIDE, no
CubeMX, no ST account, no external project: the build compiles ST's HAL and CMSIS from a
pinned checkout, generates everything board-specific, and links with a pinned GCC.

See [setup.md](setup.md) for the one-time install and for describing a board of your
own. See [build.md](build.md) for build, flash, serial and troubleshooting.

The name `stm32cube` means the STM32Cube HAL — the library — not the IDE that shares
its branding. The IDE plays no part here.

## Three layers

Everything board-specific lives in data, split by what kind of fact it is:

- **Family** (`family/stm32f4.rb`): what is true of every STM32F4 — where the HAL sits,
  how a clock profile becomes code, the DWT delay, the linker layout. A new family
  (F0, F7) is a sibling of this file, answering the same questions.
- **Device** (`data/stm32f4/devices/*.yml`): what is true of one MCU — memory regions,
  startup file, core and FPU, GPIO ports, clock limits.
- **Board** (`data/stm32f4/boards/*.yml`): what one board wires to it — the LED, the
  virtual COM port, the I2C pins, the clock profile, the probe.

The generated `bareruby_board.h/.c` adapter is the boundary: the binding's C speaks
logical ids (`bareruby_board_uart(0)`) and never a HAL handle's name, which is what
lets one binding serve every board.

## Boards

| target | short | board | MCU |
| --- | --- | --- | --- |
| `stm32-nucleo-f446re` | `f446` | NUCLEO-F446RE | STM32F446RE |
| `stm32-nucleo-f401re` | `f401` | NUCLEO-F401RE | STM32F401RE |
| `stm32-f4discovery` | `f4disco` | STM32F4DISCOVERY | STM32F407VG |

A board this table does not carry is a YAML file in your project's
`config/stm32cube/boards/` — `./bareruby init stm32` writes a commented template
there, and [setup.md](setup.md) walks through filling it in. On one key the project's
file wins over the gem's, and the build manifest records which layer answered.

## Workflow

```sh
# once per desk
gems/bareruby_prot-binding-stm32cube/lib/bareruby_prot/binding/stm32cube/install.sh

# then, as for every other board
./bareruby build samples/heartbeat.rb --target=f446
./bareruby deploy samples/heartbeat.rb --target=f446
```

`build` writes the ELF, map and manifest into `build/<composition>/`. `flash` writes it
through OpenOCD over the board's ST-LINK: write, verify, reset.
