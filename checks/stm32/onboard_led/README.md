# STM32 onboard LED checks

These checks hold the onboard LED binding to fixed answers. The class deliberately
carries no pin number — the board manifest says the LED is PA5, the NUCLEO-F446RE's
LD2, driven active-high — and the emulated machine already wires PA5 to an LED model,
so every answer is read off that model and port A's registers. Each Ruby program says
only a marker over the UART; `expected/` is the reviewed answer. Run them for the
recorded NUCLEO-F446RE target with:

```sh
checks/stm32/onboard_led/check.sh f446
```

| check | contract |
| --- | --- |
| `on_wire` | `on` lights the LED model with no pin named anywhere in the program |
| `off_after_on` | `off` returns a lit LED to dark — ODR bit 5 back to zero under active-high |
| `write_cycle` | `write(1)`/`write(0)` fold onto `on`/`off`, and a final `write(2)` pins the zero/non-zero contract; the mid-run read sees the lit stretch |
| `init_state` | `new` alone settles the LED dark — the binding's init writes an explicit off last |

Results are kept under `.bareruby/checks/stm32/onboard_led/<check>/`. `uart.txt` is the
marker; `observed.txt` is the LED-state and register reads compared against
`<name>.registers`. A failed comparison leaves its `.diff`; a passing one removes it.

The harness is the GPIO suite's stub-Renode flow: `bareruby emulate` builds against a
stub, and the one real Renode run is the harness's own, observations said before quit.
One extension: a check with `during:` in `checks.yml` gets its probe said between two
slices of the run, which is how `write_cycle` sees the LED mid-cycle.

There is no runtime refusal to test — the constructor takes nothing and `write` folds
any value to a truth — so the only refusal is at compile time: a board whose manifest
carries no `led:` is refused while units resolve, before any C exists. All three boards
this repository records carry one, so that check waits for an LED-less manifest
(`testcase.md` keeps it). The register expectations — MODER holding its reset value and
the USART2 pins, ODR bit 5 — belong to this board; an active-low board keeps the same
`True`/`False` answers (the machine's LED `invert:` absorbs polarity) with inverted ODR
expectations.
