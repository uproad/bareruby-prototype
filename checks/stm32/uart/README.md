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

Results are kept under `.bareruby/checks/stm32/uart/<check>/`. `uart.txt` is the raw
answer used by every check. `frame/registers.txt` is the four register reads. A failed
comparison leaves its `.diff`; a passing comparison removes it.

The four default-capacity checks generate their input from one repeating byte pattern.
The resume check feeds two groups at different virtual times, so the first fills the
ring before the program frees slots and the second proves those slots can be reused.
The wrap check feeds three 100-byte groups with time to consume between them, separating
index wraparound from overflow.

The register expectation belongs specifically to the NUCLEO-F446RE clock and USART2
wiring. Another STM32 board gets its own expected register answer rather than inheriting
figures that describe this one.
