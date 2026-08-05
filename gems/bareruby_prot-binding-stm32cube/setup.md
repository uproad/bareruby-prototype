# STM32 environment setup

One command installs everything an STM32 build reaches for, pinned by version and
checksum, under the project's `.tools/`:

```sh
gems/bareruby_prot-binding-stm32cube/lib/bareruby_prot/binding/stm32cube/install.sh
```

Run it from the project root. It is idempotent — a directory already at its pinned
version is left alone — so running it again after a lock change installs only what
changed. No ST account is needed at any point.

## What it installs

Everything is named in `data/sources.lock.yml`, beside the code that reads it. Nothing
says `latest`; archives are verified by SHA-256 and repositories by commit before
anything is used.

| what | from | pinned by |
| --- | --- | --- |
| ARM GCC 13.2 (xPack) | `xpack-dev-tools/arm-none-eabi-gcc-xpack` | release + SHA-256 |
| OpenOCD 0.12 (xPack) | `xpack-dev-tools/openocd-xpack` | release + SHA-256 |
| STM32CubeF4 1.28.3 | `STMicroelectronics/STM32CubeF4` | tag + commit + submodule commits |

The xPack binaries are community builds rather than Arm's own releases, which is part
of why the hash is not optional. A desk that keeps its own toolchain says so in the
environment, and the lock still names the SDK:

```sh
export ARM_TOOLCHAIN_PATH=/path/to/arm-gnu-toolchain   # contains bin/arm-none-eabi-g++
export OPENOCD=/path/to/openocd                        # the binary itself
```

`install.sh --data` additionally fetches `STM32_open_pin_data`, which only the manifest
update tooling reads — a build never does.

### Ruby 4

The compiler uses Prism, which ships with Ruby 4. `ruby --version` should say 4.x; a
Ruby kept in a private directory goes on `PATH` first.

## Describing a board of your own

A custom board is a YAML file in your project, not an edit to this gem. `init` writes
commented templates into the directories a build already reads:

```sh
./bareruby init stm32
```

Rename `config/stm32cube/boards/my_board.yml.sample` to `<key>.yml` — the `.sample`
suffix is what keeps a template from being a target — and edit it into the board:

```yaml
# config/stm32cube/boards/my_board.yml
key: my_board
name: stm32-my-board
family: stm32f4
device: stm32f401retx        # any device either layer defines
clock:
  source: hsi
  pll: { m: 16, n: 336, p: 4, q: 7 }
  ahb_divider: 1
  apb1_divider: 2
  apb2_divider: 1
  regulator_scale: 2
led:
  pin: PB0
  active_high: true
uart:
  - id: 0
    instance: USART2
    tx: { pin: PA2, af: 7 }
    rx: { pin: PA3, af: 7 }
    stdout: true
probe:
  openocd: { interface: stlink, target: stm32f4x }
```

The build proves the clock profile against the device's limits before generating any C,
and refuses a wire to a port the package does not bond out. What the board does not
declare, programs cannot reach: no `led:` means `OnboardLED` is a compile-time refusal
with the manifest's path in it.

A new MCU of a supported family is the same move under `config/stm32cube/devices/` —
copy the nearest `data/stm32f4/devices/*.yml` and change what the datasheet says.

**On one key, your file wins.** Naming a board key this gem already carries replaces
the gem's record for this project — the path for correcting official data without
waiting for a release. The build manifest records `board_source = project:…` whenever
that happens, and whole files replace; there is no field-level merge.

## The layers, for orientation

- `family/stm32f4.rb` — what is true of every F4: HAL layout, clock arithmetic, DWT
  delay, linker layout. F0 and F7 arrive as siblings of this file.
- `data/stm32f4/devices/` — facts of the silicon.
- `data/stm32f4/boards/` — facts of the wiring.
- `config/stm32cube/` in your project — your boards and devices, same shapes.
