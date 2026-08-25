# STM32 ADC checks

These checks hold the STM32 ADC binding to fixed answers. The pinned Renode 1.16.1
models no F4 ADC — its STM32 converters are all the F0/L0/G0 register layout — so the
converter here is this suite's own C# model (`model/BareRubyCheckAdc.cs`), compiled by
Renode at run time exactly as the I2C suite's check sensor is. A check gives each
channel its voltage in millivolts; a conversion answers `value * 4095 / 3300` in
integer arithmetic, so 0 mV is 0x000, 3300 mV is 0xFFF, and 1650 mV lands on 0x7FF.
Each Ruby program asks one question, reports over the UART, and `expected/` is the
reviewed answer. Run them for the recorded NUCLEO-F446RE target with:

```sh
checks/stm32/adc/check.sh f446
```

| check | contract |
| --- | --- |
| `read_raw_levels` | both ends of the 12-bit range and the middle arrive as raw values, and a voltage changed mid-run is seen by the next read |
| `read_raw_byte_edges` | the raw values whose bytes are likeliest to be mangled — 255, 256 and 3840 — arrive exact |
| `read_voltage_scale` | `read` and `read_voltage` answer the same Fixed, scaled against the 3.3 V full scale by the pico_sdk precedent |
| `pin_channel_map` | the six analog pins of the board's table land on their own ADC1 channels, across ports |
| `analog_moder` | initialization puts the pin in analog mode — MODER bits `11` — and touches nothing else on the port |
| `adc_registers` | the channel lands in SQR3's first rank, its sample time in SMPR2, the conversion settings in CR2 with ADON down after the stop, and the prescaler in the common CCR |
| `invalid_pin` | a pin number outside any port is refused before touching anything |
| `non_analog_pin` | a bonded-out pin on no row of the board's ADC table is refused through the table's default case |

Pin numbers run sixteen to a port, port A first, as everywhere: PA0 is 0, PB0 is 16,
PC0 is 32. The board's `adc:` table carries the Arduino header's A0–A5.

The harness runs `bareruby emulate` with a stub standing in for Renode, then runs the
real Renode once itself on the transformed script: the model included and attached at
0x40012000, the `give:` voltages set before the run, each `steps:` entry applied after
slicing 0.4 virtual seconds off it, and any `observe:` register reads said before
quit. Results are kept under `.bareruby/checks/stm32/adc/<check>/`; `uart.txt` is the
answer, `observed.txt` the register reads, and a failed comparison leaves its `.diff`.

What the emulator cannot hold — real voltage accuracy, the reference's actual value,
sample-time electrical behaviour — stays recorded for hardware in `testcase.md`.
