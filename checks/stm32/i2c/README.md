# STM32 I2C checks

These checks hold the STM32 I2C binding to fixed answers. Unlike the UART, an I2C
transaction needs somebody on the other end: every check runs against the check sensor —
a small C# `II2CPeripheral` in `sensor/` that Renode compiles at run time and attaches
to I2C1 at address `0x76`. Each Ruby program asks one question, reports over the UART,
and `expected/` is the reviewed answer. Run them for the recorded NUCLEO-F446RE target
with:

```sh
checks/stm32/i2c/check.sh f446
```

| check | contract |
| --- | --- |
| `write_result` | `write` completes against the sensor and returns the byte count |
| `write_echo` | written bytes reach the sensor intact, proved by reading them back |
| `read_single` | a one-byte read answers real data and its exact size |
| `read_multi` | two-byte (HAL's POS path) and four-byte (BTF path) reads answer real data — against the count-ignoring check sensor |
| `read_register` | the `outputs` argument selects where the read starts |
| `payload_shapes` | integers, arrays, strings and an `Arena::String` assemble into one transaction |
| `write_all_byte_values` | all 256 byte values — 0x00 and 0xFF included — cross the write path; the sensor scores mismatches and how many arrived |
| `read_pattern` | a sixteen-byte read arrives complete and in order |
| `frequency_registers` | 100 kHz standard mode reaches I2C1's CR1, CR2, CCR and TRISE |
| `frequency_fast` | 400 kHz fast mode reaches the registers through the DeInit → Init path |
| `invalid_address` | an address beyond seven bits is refused before touching the bus |
| `missing_device` | records a known gap, not a correct answer: with nobody at the address the binding waits forever (`HAL_MAX_DELAY`), so `-1` never comes back |

Results are kept under `.bareruby/checks/stm32/i2c/<check>/`. `uart.txt` is the raw
answer used by every check. `<name>/registers.txt` is the four register reads of the
frequency checks. A failed comparison leaves its `.diff`; a passing comparison removes it.

## How a check runs

`bareruby emulate` builds the firmware and writes the machine and run scripts, but it
runs Renode against the plain machine — where an I2C program hangs against nobody. So
the harness hands the emulate verb a stub in place of Renode (satisfying it with an
empty UART capture), then transforms the generated `run.resc` — the sensor's C# included
before the machine exists, the device attached right after the platform loads, any
register probe said before quit — and makes the one real Renode run itself.

## The sensor's contract

The first byte of every write selects a register; further bytes store from there through
a sixteen-byte file that starts as the pattern `0xF0..0xFF`. A read answers everything
from the selected register to the end of the file, **ignoring the requested count**.
That is load-bearing: the pinned Renode 1.16.1 `STM32F4_I2C` controller asks a slave for
data with `count = 1` and does not model the POS bit HAL's two-byte receive leans on
([renode#114](https://github.com/renode/renode/issues/114)), so against a slave that
honors the count — the bundled `Mocks.DummyI2CSlave` among them — a two-byte read
silently answers `0x00` for its second byte and longer reads hang in
`I2C_WaitOnFlagUntilTimeout`. A slave that answers its whole tail makes 1..N byte reads
arrive as real data; upstream rewrote the controller after 1.16.1, but no stable release
carries the fix yet. That workaround also bounds what the read checks claim: they prove
the binding and HAL's receive paths against this count-ignoring sensor under Renode —
the count contract with a real slave, POS and BTF included, lives on hardware. Two
registers sit outside the file: writes selecting `0x40` are scored against a rolling
`0x00..0xFF` counter, and a read selecting `0x41` answers mismatches and bytes received
as `MMM/CCC`, three ASCII digits each — the count is what catches a chunk that never
arrived.

What these checks deliberately do not claim is timing: the model moves data in zero
virtual time and stores CCR and TRISE without using them, so the frequency checks pin
the binding's arithmetic reaching the registers, not the SCL wire. Clock stretching,
NACK handling on real silicon, the repeated start joining a read's select and its
receive (a read with `outputs` is one `HAL_I2C_Mem_Read` transaction; without them, a
bare `HAL_I2C_Master_Receive`), and electrical behavior live on hardware with a logic
analyzer — `testcase.md` keeps that list. `missing_device` pins today's answer to a
missing device — a hang, because the binding waits with `HAL_MAX_DELAY` where real
silicon would NACK — until the binding decides between a finite timeout and the status
quo, at which point its expectation changes to the new contract. The same decision owns
the read path, which today answers a HAL error with `bareruby_board_fault()` rather
than any return value.

The register expectations belong specifically to the NUCLEO-F446RE clock (APB1 at
42 MHz) and I2C1 wiring. Another STM32 board gets its own expected register answers
rather than inheriting figures that describe this one.
