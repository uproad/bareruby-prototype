# STM32 clock checks

Every register expectation in the UART, I2C and GPIO suites stands on one premise:
SYSCLK at 84 MHz, APB1 at 42 MHz. These checks pin the premise itself — the board
manifest's clock profile (HSI through PLL m16/n336/p4, AHB ÷1, APB1 ÷2, APB2 ÷1,
regulator scale 3) reaching the RCC, FLASH and PWR registers. Observation only: each
sample says a marker over the UART and stops, and the harness reads the registers.
Run them for the recorded NUCLEO-F446RE target with:

```sh
checks/stm32/clock/check.sh f446
```

| check | contract |
| --- | --- |
| `pll_registers` | the manifest's PLL values land in PLLCFGR's fields — `0x22015410` |
| `tree_dividers` | the switch to PLL and the bus dividers land in CFGR — `0x0000100A`, PPRE1 ÷2 being the very bit APB1 = 42 MHz stands on |
| `oscillator_control` | HSI stays on and PLLON arrives — CR `0x03000483` |
| `flash_latency` | two wait states for 84 MHz land in FLASH ACR |
| `regulator_scale` | scale 3 lands in PWR CR's VOS, with VOSRDY answering |

Results are kept under `.bareruby/checks/stm32/clock/<check>/` — `uart.txt` for the
marker, `observed.txt` against `<name>.registers`. A failed comparison leaves its
`.diff`; a passing one removes it. The harness is the stub-Renode flow shared with the
other suites, the observation said before quit.

Two bounds on what this proves. Measuring time in the emulator would be circular for
this profile: the machine's DWT and SysTick frequencies are written out of the same
clock arithmetic the firmware uses, so only the register reads are a non-circular
check — the frequencies themselves live on hardware (MCO measurement, UART baud
accuracy; `testcase.md` keeps the list). And the pinned Renode's models answer ready
bits as instant mirrors of the on bits, hold FLASH ACR's cache/prefetch bits as
unimplemented tags (dropped writes, zero reads — the OTYPER treatment), and give PWR
CR a reset value unlike the reference manual's, so the PWR expectations are recorded
model measurements rather than silicon values. An invalid profile never reaches these
registers at all — the binding's clock arithmetic refuses it at build time.
