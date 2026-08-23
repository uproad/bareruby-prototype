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

Results are kept under `.bareruby/checks/stm32/uart/<check>/`. `uart.txt` is the raw
answer used by every check. `frame/registers.txt` is the four register reads. A failed
comparison leaves its `.diff`; a passing comparison removes it.

The register expectation belongs specifically to the NUCLEO-F446RE clock and USART2
wiring. Another STM32 board gets its own expected register answer rather than inheriting
figures that describe this one.
