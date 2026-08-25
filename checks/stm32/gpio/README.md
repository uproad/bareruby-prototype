# STM32 GPIO checks

These checks hold the STM32 GPIO binding to fixed answers. Outputs need no counterpart:
the emulated machine already wires PA5 to an LED model, the board's LD2. Inputs need a
hand on a pin, so the harness attaches Renode's button model to PC13 — the board's B1
user button, high at rest and low while pressed — and presses it mid-run. Each Ruby
program asks one question, reports over the UART, and `expected/` is the reviewed
answer. Run them for the recorded NUCLEO-F446RE target with:

```sh
checks/stm32/gpio/check.sh f446
```

| check | contract |
| --- | --- |
| `write_read_back` | `write` answers 0 and the driven state reads back through IDR, with `high?`/`low?` agreeing |
| `led_wire` | a write reaches the connection — the LED model — not just the ODR bit, with MODER keeping its reset value around the one changed pin |
| `input_level` | an externally driven input level reaches `read`, both at rest and pressed |
| `irq_falling` | a falling edge reaches the realtime handler through EXTI and the NVIC, and not before the press |
| `config_registers` | direction lands in MODER, the pulls in PUPDR, and `HIGH_Z` as input with no pull |
| `invalid_pin` | a pin number outside the range is refused before touching anything |
| `missing_port` | a pin on a port the package does not bond out is refused by the adapter's port table |

Pin numbers run sixteen to a port, port A first: PA5 is 5, PC13 is 45, PE0 is 64. The
F446RE bonds out ports A, B, C, D and H.

Results are kept under `.bareruby/checks/stm32/gpio/<check>/`. `uart.txt` is the raw
answer used by every check. `observed.txt` is the register and LED-state reads of the
observing checks, compared against `<name>.registers`. A failed comparison leaves its
`.diff`; a passing comparison removes it.

## How a check runs

`bareruby emulate` builds the firmware and writes the machine and run scripts, but it
runs Renode with no button and no observations. So the harness hands the emulate verb a
stub in place of Renode (satisfying it with an empty UART capture), then transforms the
generated `run.resc` — the button attached right after the platform loads, the run split
in two with a press between the slices where the check asks for one, any observation
said before quit — and makes the one real Renode run itself. A button press only lands
once the emulation runs again, which is why the press sits between two `RunFor` slices
rather than before the run.

## What the checks claim, and what stays on hardware

The register model is faithful storage and digital state, not electricity — and not
even storage for OTYPER, which this Renode leaves as a tagged register that drops
writes and reads zero, so the open-drain pin proves only that its init path holds.
Pull resistors never move a floating pin, and the machine has no SYSCFG — every port's pin N is wired straight to EXTI line N, so the
interrupt check proves the edge reaches the handler, while EXTICR's port selection
(that PC13's interrupt listens to port C alone) lives on hardware. `testcase.md` keeps
the hardware list.

One API gap is recorded rather than tested: the stdlib registers `EDGE_FALL` only. The
binding chooses rising when bit 4 is absent, but with no `EDGE_RISE` constant to say so,
the rising path waits for the constant.

The register expectations belong to this machine: port C resets to all zeros, port A
carries the SWD pins in its MODER reset value, and PA5 is where this board hangs its
LED. Another STM32 board gets its own expected answers rather than inheriting these.
