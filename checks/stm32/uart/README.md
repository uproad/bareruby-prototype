# STM32 UART checks

These checks hold the STM32 binding to fixed answers rather than treating the host
binding as an oracle. Each Ruby program asks one question, `input/` is what Renode puts
on USART RX, and `expected/` is the reviewed answer. Run them for the recorded
NUCLEO-F446RE target with:

```sh
checks/stm32/uart/check.sh f446
```

| check | contract |
| --- | --- |
| `rx_order` | RX bytes leave in arrival order |
| `peek` | two peeks see one byte and do not consume it |
| `gets_terminator` | `gets` stops at the line ending selected by the program |
| `rx_overflow` | a four-slot ring keeps its first three bytes and drops later bytes |
| `rx_interrupt` | RX raises the registered notification and the handler reads the byte |
| `tx_bytes` | `write` and `puts` put the exact expected bytes on TX |
| `frame` | 9600 7E1 reaches USART2's BRR, CR1, CR2 and CR3 |
| `rx_default_254` | the default ring keeps 254 bytes in order |
| `rx_default_255` | all 255 usable slots of the default ring hold data |
| `rx_default_256` | the 256th byte is dropped without changing the first 255 |
| `rx_default_512` | a large overflow still leaves the first 255 bytes intact |
| `rx_resume_after_full` | freed slots receive new bytes after an overflow |
| `rx_wraparound` | 300 consumed bytes stay ordered across the ring boundary |
| `clear_rx_buffer` | clearing RX empties the ring and later bytes still arrive |
| `read_length` | `read(3)` returns exactly three bytes and leaves two queued |
| `rx_empty` | an empty RX ring answers zero and `-1` without consuming data |
| `line_ending_tx` | a selected CRLF ending reaches TX as exact raw bytes |
| `setmode` | changing the whole frame at runtime reaches the USART registers |
| `setmode_partial` | changing only baud rate preserves the other frame fields |
| `write_result` | `write` returns the number of bytes placed on TX |
| `rx_interrupt_multiple` | one handler receives three queued bytes in order |
| `tx_interpolation` | an interpolated `write` adds no ending, an interpolated `puts` adds one, and a 64-bit value crosses the printf path intact |
| `rx_all_byte_values` | all 256 byte values — 0x00 and 0xFF included — cross the queue unchanged |
| `gets_crlf` | a two-byte CRLF ending stops `gets` at its final byte |
| `gets_across_feed` | `gets` waits on a half line and completes it when the rest arrives |
| `read_across_feed` | `read` waits below its count and returns when the rest arrives |
| `irq_shared_queue` | the handler and the program consume one queue; a byte the handler took is gone |
| `irq_overflow` | a registered handler does not change the full ring's keep-first policy |
| `irq_clear_rx_buffer` | clearing inside the handler empties the ring and later bytes still notify |
| `frame_variants` | 19200 7O2 — odd parity, two stop bits — reaches the USART registers |
| `bytes_to_write` | after `flush`, nothing is owed to the wire |
| `clear_tx_buffer` | clearing TX under the synchronous send leaves sent bytes intact |
| `write_9n` | records a known gap, not a correct answer: 9N passes init, but HAL reads the buffer as uint16 pairs and `write "AB"` puts `41 00` on the wire |

Results are kept under `.bareruby/checks/stm32/uart/<check>/`. `uart.txt` is the raw
answer used by every check. `frame/registers.txt` is the four register reads. A failed
comparison leaves its `.diff`; a passing comparison removes it.

The four default-capacity checks generate their input from one repeating byte pattern.
The resume check feeds two groups at different virtual times, so the first fills the
ring before the program frees slots and the second proves those slots can be reused.
The wrap check feeds three 100-byte groups with time to consume between them, separating
index wraparound from overflow. That repeating pattern is 1..251, which never carries
0x00 or 0xFF — the two values most likely to break a queue built on C strings and a `-1`
empty answer — so `rx_all_byte_values` walks 0..255 instead (`pattern: full`), in two
128-byte groups the program drains between. The across-feed checks split one read the
same way: half the bytes, 20 virtual milliseconds, the rest — proving `gets` and `read`
wait rather than answer short. The interrupt checks pin the handler's contract, not its
call count, exactly as `rx_interrupt_multiple` does.

What these checks deliberately do not claim is the wire itself: break frames, the
mid-transmit `bytes_to_write` state, waveform-level frame settings and RTS/CTS live on
hardware with a logic analyzer — `testcase.md` keeps that list. One register does too:
Renode's STM32_UART model does not retain CR1's M bit (a 0x360C write reads back
0x260C), so `frame_variants` speaks 7O2 rather than a nine-bit word. The nine-bit frame
has a deeper problem than the register: under 9N the HAL reads the transmit buffer as
uint16 pairs while the binding hands it a C string, so the data itself is mangled —
`write_9n` pins that mangling as a known gap until the binding either refuses 9N or
grows a nine-bit send, at which point its expectation changes to the new contract.

The register expectation belongs specifically to the NUCLEO-F446RE clock and USART2
wiring. Another STM32 board gets its own expected register answer rather than inheriting
figures that describe this one.
