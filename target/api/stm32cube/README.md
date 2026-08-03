# STM32 platform

See [setup.md](setup.md) for required software and CubeMX project generation.
See [build.md](build.md) for build, flash, execution, serial, and troubleshooting steps.

This binding keeps the STM32 ownership boundary explicit without committing an
STM32Cube project:

- CubeMX owns the `.ioc` file, clock tree, pin mux, HAL initialization, startup,
  linker script, and the project metadata.
- BareRuby pass 12 owns the generated application, runtime, and HAL wrappers.
- The second stage copies only the translation units the Ruby program reached for into
  the Cube project, and links them against the HAL with the ARM GNU toolchain the
  freestanding boards already use. STM32CubeIDE is not involved.

The first target expects a NUCLEO-F446RE project that configures LD2, USART2 on PA2/PA3,
and I2C1 on PB8/PB9. USART2 is connected to the board's ST-LINK virtual COM port. I2C1
is configured without internal pulls, so the bus requires external pull-up resistors.

## Workflow

1. Install Ruby, the ARM toolchain and the HAL, put a Cube project under
   `.tools/stm32cube/`, and add the preserved CubeMX entry hook described in
   [setup.md](setup.md).
2. Run `./bareruby build --target=f446` as described in [build.md](build.md). It
   generates the application, synchronizes only `bareruby_*` files, writes the makefile,
   and links the ELF.
3. Write the ELF with STM32CubeProgrammer, then observe LD2 or USART2 as appropriate for
   the selected sample.

## Changing the Cube configuration

Open the `.ioc` file in STM32CubeMX, change the pins or peripherals, and generate code
normally. The integration in `main.c` is in CubeMX `USER CODE` sections, so regeneration
preserves both the `bareruby_entry.h` include and the call made after all `MX_*_Init`
functions.

Build again after regeneration. The current NUCLEO-F446RE binding expects
`LD2_GPIO_Port`, `LD2_Pin`, `huart2`, and `hi2c1`. If those names change, its pass-12
STM32 wrapper must change with them.

## Current binding contract

| BareRuby API | F446 implementation |
| --- | --- |
| `OnboardLED` | LD2 on PA5 through HAL GPIO |
| `GPIO` | HAL GPIO, encoded as `port_index * 16 + pin`; PA0 is 0, PB0 is 16, PC13 is 45 |
| `UART.new(0, ...)` | `huart2`, blocking transmit and receive |
| global `puts` | newlib `_write` through USART2 |
| `I2C.new(1, ...)` | `hi2c1`, blocking master transfers |
| `sleep`, `sleep_ms`, `asleep` | HAL tick |
| `Machine.delay_us` | Cortex-M4 DWT cycle counter |

I2C direct reads and reads with one-byte or two-byte register addresses are
implemented. HAL memory reads provide the repeated-start transaction for the latter
two forms. Longer output prefixes on a read are rejected instead of silently changing
the transaction. PWM, ADC, and GPIO interrupts are not part of this first STM32 slice.

The generated LED, UART receive, and I2C firmware translation units have been compiled
and linked against a user-owned STM32F4 HAL project. SWD programming, LD2, and USART2
output have been exercised on a physical NUCLEO-F446RE; I2C has been linked but not
verified on hardware. Those hardware runs predate the move off STM32CubeIDE and were
built by its headless builder; the current second stage has been verified by building,
not by flashing. The Cube project itself is deliberately not committed here.

## Sample compatibility notes

The lists below describe whether each top-level program under `samples/` works unchanged
with the current NUCLEO-F446RE binding and the documented `--no-exceptions` build. Text
written with `puts` is sent through USART2. I2C samples still require the corresponding
external devices and pull-up resistors.

Supported samples:

- `heartbeat.rb` — blinks the board's LD2 through `OnboardLED`.
- `uart_receive.rb` — reads from USART2 through `UART.new(0, ...)`.
- `i2c.rb` — uses the configured I2C1 peripheral.
- `array.rb` — uses platform-independent fixed-capacity arrays.
- `definite_assignment.rb` — uses platform-independent optional-value semantics.
- `features.rb` — uses control flow, strings, symbols, and USART2 output.
- `fixed.rb` — uses platform-independent Q16.16 arithmetic and USART2 output.
- `implicit_return.rb` — uses platform-independent method return semantics.
- `nilable.rb` — uses optional values and arena-backed strings.
- `object.rb` — uses platform-independent objects and references.
- `require.rb` — expands `require_lib.rb` and `require_helper.rb`; those two files are
  support files rather than standalone samples.
- `string.rb` — uses arena-backed strings and USART2 output.

Samples not yet supported unchanged:

- `blink.rb` — uses Pico GPIO 25 instead of `OnboardLED`; on STM32 the number encodes
  PB9, not the NUCLEO LD2 pin.
- `logger.rb` — UART is supported, but its Pico button pin 14 maps to STM32 PA14/SWCLK
  and must be changed to a suitable input; the NUCLEO user button on PC13 is encoded as
  pin 45.
- `interrupt.rb` — the STM32 GPIO interrupt wrapper is not implemented.
- `servo.rb` — the STM32 PWM wrapper is not implemented.
- `adc.rb` — the STM32 ADC and PWM wrappers are not implemented.
- `asleep.rb` — timing and GPIO are supported, but the STM32 ADC wrapper is missing and
  its GPIO numbers are Pico-specific.
- `avs.rb` — requires the missing STM32 ADC and PWM wrappers and board-specific pin
  mapping.
- `tenji.rb` — requires the missing STM32 ADC and PWM wrappers and board-specific pin
  mapping.
- `tenji_int.rb` — requires the missing STM32 ADC and PWM wrappers and board-specific
  pin mapping.
- `m25.rb` — uses `begin`/`rescue`; the documented STM32 build disables C++ exceptions.
- `arena.rb` — tests exception-based arena recovery; the documented STM32 build disables
  C++ exceptions.

Clean links have been verified for representative programs from each supported
runtime/peripheral group: `heartbeat.rb`, `string.rb`, `uart_receive.rb`, and `i2c.rb`.
