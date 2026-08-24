# STM32 PWM checks

These checks hold the STM32 PWM binding to fixed answers. The binding mirrors the Pico
binding's design: the board hands over a timer already prescaled to tick at one
microsecond, so a period is its length in microseconds and a pulse width is the compare
value itself. Which timer answers a pin is the board manifest's PWM table — the program
only ever says the pin. Run them for the recorded NUCLEO-F446RE target with:

```sh
checks/stm32/pwm/check.sh f446
```

| check | contract |
| --- | --- |
| `method_answers` | the four calls answer the setting they just applied — 50, 50, 50.0, 7.5 |
| `frequency_registers` | 50 Hz lands as PSC 83 and ARR 19999 with the counter running, through `frequency:` and `period_us` alike |
| `duty_registers` | a quarter duty lands as compare value 5000 with the channel in PWM mode 1, enabled |
| `pulse_width_registers` | 1500 µs is compare value 1500 — and PC7 pulls the TIM3, channel-2, AF2 row of the table |
| `af_registers` | the pin lands in alternate function 1 with the reset value and the USART2 wiring preserved around it |
| `duty_wave` | the compare output drives the LD2 wire and holds duty 0.3 under Renode's LED tester |
| `duty_bounds` | 0 and 100 per cent answer 0.0 and 100.0 and land as no pulse and the whole period |
| `no_timer_pin` | a pin on no row of the table is refused before anything is touched |

Results are kept under `.bareruby/checks/stm32/pwm/<check>/`. `uart.txt` is the raw
answer; observing checks compare `observed.txt` against `<name>.registers`, and
`duty_wave` compares the LED tester's success marker against `<name>.duty`. A failed
comparison leaves its `.diff`; a passing one removes it. The harness is the stub-Renode
flow shared with the other suites, with the sleep suite's duty mechanism: a failed
`AssertDutyCycle` aborts the script, so the marker after it is only said on success.

Two bounds on the claims. The pinned Renode's `STM32_Timer` retains the registers and
drives the compare output to the GPIO with real PWM-mode-1 polarity — but it drops
CCMR1's OC1PE preload bit (written by the HAL, read back zero), so that expectation is
the recorded model measurement and the bit lives on hardware, the OTYPER treatment.
And virtual time proves ratios and registers, not electricity: real waveform frequency,
edges and the servo's pulse stay on hardware — `testcase.md` keeps the list, along with
the one open design question, what an inexpressible frequency should do (today the
arithmetic flows through unclamped).

The register expectations belong to this board's table (PA5 and PA15 on TIM2 channel 1,
PC7 on TIM3 channel 2) and its 84 MHz timer clock. Another board gets its own table and
its own answers.
