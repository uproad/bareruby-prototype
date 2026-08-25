# STM32 sleep and timing checks

These checks hold the sleep binding to fixed answers, standing on the one thing the
emulator gives that hardware cannot: deterministic virtual time. The machine's DWT and
SysTick run at the proved 84 MHz, so an elapsed millisecond count is a single exact
number, not a tolerance band. Programs measure themselves with `ticks_ms` and report
over the UART; `expected/` is the reviewed answer. Run them for the recorded
NUCLEO-F446RE target with:

```sh
checks/stm32/sleep/check.sh f446
```

| check | contract |
| --- | --- |
| `sleep_result` | `sleep_ms` answers the milliseconds it was given — negative included — and only the wait is clamped at zero |
| `sleep_elapsed` | 100 ms elapses as exactly 100, 1 ms as 2 — the HAL's polling granularity, pinned |
| `sleep_seconds` | `sleep(1)` answers 1 and costs 1000 ms |
| `sleep_drift` | a 20 ms body stretches a `sleep_ms(100)` lap to 120 — sleep counts from the call |
| `asleep_cadence` | the same body leaves an `asleep_ms(100)` lap at 100 — asleep counts from the period mark |
| `asleep_overrun` | an overrun lap costs its body and re-anchors the mark at now, no debt carried |
| `blink_duty` | the even blink holds duty 0.5 over two virtual seconds, asserted by Renode's LED tester |
| `heartbeat_duty` | 100 ms on / 900 ms off holds duty 0.1 — the hand-run record in `checks/emulate.yml` made an assertion |
| `sleep_interrupt_delivery` | a byte injected into an `interrupt: false` wait is not delivered there, not lost, and spoken in the next default wait |
| `asleep_us_stale_mark` | records a known fault: `asleep_us` delays for its promise but moves no mark and delivers nothing, so the overdue `asleep_ms` after it returns at once without ever draining |

Results are kept under `.bareruby/checks/stm32/sleep/<check>/`. `uart.txt` is the
program's own measurements; the duty checks also compare `duty.txt` — the success
marker of the LED tester — against `<name>.duty`. A failed comparison leaves its
`.diff`; a passing one removes it.

The harness is the stub-Renode flow shared with the other suites, with two moves of
its own. A check with `feed:` gets its bytes said to the USART between two slices of
the run, so they land mid-wait. A check with `duty:` trades the timed run for
`CreateLEDTester` and `AssertDutyCycle` — a failed assertion aborts the script, so the
`InfoLog` marker after it is only ever said on success, and that marker is what the
expectation reads.

What stays on hardware is the clock itself: virtual milliseconds prove the arithmetic
and the contracts, not that a real millisecond passes. Real-time accuracy and the
microsecond pulse width live there — `testcase.md` keeps the list, along with the
recorded `asleep_us` fault whose expectation changes when the binding gives it the
same wait path as the other two.
