# Sample programs

The BareRuby programs this prototype is exercised with. Run one from the repository
root:

```sh
./brd samples/blink.rb            # first stage, second stage, flash
ruby compile.rb samples/blink.rb  # first stage only
```

The toolchain and the build steps are in the [top-level README](../README.md), and the
milestones these programs stand for are in [`HISTORY.md`](../HISTORY.md). `ref.rb` — the
representative program from the design
documents — stays at the repository root, because it is what `compile.rb` compiles when
it is given no argument.

| File | What it covers |
| --- | --- |
| `blink.rb` | Demo 1 — GPIO |
| `heartbeat.rb` | `OnboardLED`, which blinks every supported board unchanged — including boards whose LED is not a GPIO |
| `interrupt.rb` | GPIO falling-edge interrupt feasibility |
| `servo.rb` | Demo 2 — PWM with keyword arguments, a peripheral held in an ivar |
| `logger.rb` | Demo 3 — UART, interpolation, `if`, folded constant flags |
| `uart_receive.rb` | UART `read` and `gets` returning variable-length strings from the current arena |
| `uart_one_queue.rb` | One receive queue that everyone reads: `peek`, `gets` and `bytes_available` about the same bytes, what nobody took still there afterwards, and `clear_rx_buffer` emptying it |
| `uart_on_line.rb` | UART receive interrupt: `on_line` handing each completed line to a realtime handler as a `StringView`, drained while `sleep_ms` waits |
| `uart_buffered.rb` | Arduino HardwareSerial-shaped receive: `bytes_available`/`read_byte`/`peek` over the interrupt-fed ring, `stop_bits:`, and a timeout read composed from `ticks_ms` |
| `uart_format.rb` | The frame the standard guideline states — `data_bits:`/`stop_bits:`/`parity:` asked for as 7E1 — plus `bytes_to_write` and `send_break`. A frame a device cannot produce is refused, never replaced |
| `peripheral_ruby.rb` | A peripheral class carrying Ruby: `can_read_line` written once in the gem that declares UART, and a method the program adds to the same class |
| `i2c.rb` | I2C mixed-output write and repeated-start read returning a variable-length string |
| `nilable.rb` | `nil`, inferred `T?`, tagged values, `nil?`, local `&.`, `if`/`while` narrowing, `||`, missing `else`, and assignment on one path |
| `definite_assignment.rb` | `T?` for locals first assigned in an `if` or `while`, a missing-`else` `if` value, and an ivar not assigned on every `initialize` path. Matches Ruby |
| `features.rb` | Control flow, strings, symbols. Output matches real Ruby exactly |
| `fixed.rb` | `Fixed` arithmetic. Q16.16, so it deliberately differs from Ruby's Float |
| `m25.rb` | Inheritance, modules, `super`, begin/rescue, interpolation assignment. Matches real Ruby |
| `adc.rb` | Demo 4 — ADC read scaled through `Fixed` and driving a PWM duty cycle |
| `array.rb` | Fixed-capacity arrays, as locals and as an instance variable. Matches real Ruby |
| `arena.rb` | `arena(N)` as a form: nested blocks as release points, `arena` without a size, methods that allocate without being handed a region, growing arrays (`Arena::Array`, `[]`, `[]=` past the end, `<<`), `::Array` for the fixed-capacity one, a region left by an exception, and the three ways of running one out — all caught and carried on from |
| `string.rb` | Variable-length strings in a region: `Arena::String.new`, the empty literal `""` as sugar for it, grown, aliased, joined, compared, duplicated, and one built from an interpolation measured while running |
| `asleep.rb` | `asleep` in all three units: a 10 kHz square wave, a 100 Hz sampling loop, and a one second turn around work whose length varies |
| `sleep_interrupt.rb` | A wait is where a notification handler runs: `asleep_ms` delivers what arrived, and `interrupt: false` holds it back without losing a byte |
| `tenji.rb` | A PicoRuby product ported over: three ADC channels driving three PWM LEDs |
| `tenji_int.rb` | The same program with `Fixed` replaced by integer arithmetic |
| `avs.rb` | The same purpose met properly: 40 kHz sampling, a 30 ms window of frames, a swing per channel. Its detectors set their bounds through a helper `initialize` calls. Its heartbeat is `OnboardLED`, so it says it is alive on any board rather than only on one whose LED is a pin |
| `require.rb` | require expansion, with `require_lib.rb` and `require_helper.rb` requiring each other |
| `object.rb` | An object passed to a method, aliased, held by another object and handed back. Matches real Ruby |
| `implicit_return.rb` | Methods ending on a call, a `puts`, an `if` and a `while`, and one whose last expression is its value. Matches real Ruby |
| `block_parameters.rb` | A block and its sender disagreeing on how many: a value nobody named is dropped, a name nothing was handed to is nil — in a counted loop and in a realtime handler alike |
| `gpio_pico_loop.rb` | How much a peripheral call costs, read off a pin. Every GPIO a Pico 1 brings out to its header, pulsed one after another with nothing between the writes, so the period of GP0 is one whole sweep and nothing but the writes is on the path |

## A product ported over

`tenji.rb` is the first program here that was not written for BareRuby: it is a
PicoRuby product (three audio channels read through the ADC, peak-to-peak over a
20-sample window, driving three PWM LEDs, with a watchdog LED on GP25) ported over to
find out what the language is still missing. What the port had to change:

| Original | Ported | Why |
| --- | --- | --- |
| `require "pwm"` / `require "adc"` | dropped | Peripherals are built in |
| `sleep(0.01)` | `sleep_ms(10)` | `sleep` takes whole seconds |
| `d26.minmax` | an explicit loop in `Window#span` | No iteration or folding methods yet |
| `x.clamp(0.0, 1.0)` | two modifier `if`s | `clamp` would need one method with two types |
| `p6.duty(duty26)` | `p6.duty(duty26.to_i32)` | Bindings take one argument type |
| `wd_res = 1.0 / loop_sleep_time` | `wd_res = 1000 / loop_sleep_ms` | Integer where a fraction was not needed |
| a `def` at the top level | a class | Top-level methods are not implemented |

`GPIO.new(25, 2)` needed no change: 2 is `GPIO::OUT` in both languages now. The port
keeps the original structure and behaviour otherwise, with one deliberate exception: the
original's decay block guards all three channels on `m26`, which is a copy-paste slip, so
each guard here reads its own maximum.

`tenji_int.rb` is the same program with `Fixed` replaced by integer arithmetic. The
converter is read with `read_raw`, and every ratio is carried in units of 1/4096 — which
is the resolution the 12-bit converter already delivers, so nothing is lost. `span / 3.3`
then disappears, because the raw span *is* the ratio, and with it go nine 64-bit divisions
and three 64-bit multiplications per iteration. `text` drops from 16220 B to 14852 B, and
the loop from roughly 2900 to roughly 2050 cycles. What remains is dominated by the three
ADC conversions, which cost 2 µs each in the converter itself.

## The same purpose, met properly

`avs.rb` meets that program's purpose rather than approximating it. Reading three
channels every 10 ms samples the audio at 100 Hz, so nothing above 50 Hz is measured and
the peak-to-peak window sees aliases rather than the signal. That is the part PicoRuby's
speed forced. Here `asleep_us(25)` samples at 40 kHz and holds the period instead of
adding the body's cost to it, which puts Nyquist at 20 kHz and covers the audible band.
Peak to peak over 30 ms cannot be a scan of the window at that rate — 1200 samples per
channel on every sample — so the window is a ring of six 5 ms frames: a sample updates
the current frame's extremes in two comparisons, and closing a frame folds twelve values,
six lows and six highs, into the span of the whole window.

Everything the original wraps around that window is kept, because none of it is a
workaround. The three channels carry three different sources at three different sound
pressures, so a fixed reference would leave the quiet ones dark: each channel keeps its
own full swing, raised by any span that exceeds it and decayed towards a floor over ten
seconds. Ten is the figure the original settled on, and it is what lets a quiet track
light up after a loud one without a loud passage being forgotten inside a track. A span
under the gate is silence and lights nothing, so a channel with nothing plugged into it
stays dark instead of amplifying its own noise. The port's `duty * 120 / one - 10` is
that gate in the original's terms — ten points cut off the bottom, and the 1.2 restoring
the top those ten points cost.

The PWM frequency drops from 100 kHz to 5 kHz for the same reason: `duty` is a percentage
and the binding sets the wrap to `1000000 / frequency - 1`, so at 100 kHz the top is 9 and
a percentage can only reach ten levels. At 5 kHz it is 199, which is every percent, and
still far above flicker fusion. Four objects carry the program, divided by mechanism
rather than by data: `PeakToPeakDetector` owns a converter and answers with the peak to
peak of the last 30 ms, `AudioVisualizer` keeps one channel's swing and turns a span into
a brightness in percent, `Led` owns a PWM slice and takes that brightness, and
`Heartbeat` blinks the board's own indicator. It reaches it through `OnboardLED` rather
than through GP25, which is where the LED sits on a plain Pico and where a wireless board
puts the radio's select line instead — the same six lines say "still running" on every
board this way. It writes only when the state changes, because a board that reaches its
LED through a radio pays a bus transaction for each write and this loop ticks 40,000
times a second. None of them holds another. The loop is what joins them — it
takes a span from a detector, passes it to the visualizer and hands the answer to an LED
— which is the work a controller exists to do. Input, policy and output change for
different reasons: the window scheme, the gain rule, the output device. PWM is the last
of those, a detail the other two never see. Detecting the peak to peak stays one class
for the same test read the other way — splitting the frame's extremes and the ring back
out of it yields classes too small to be read apart, and a min/max abstraction shared
between the frame and the fold has to carry an emptiness flag and a branch per sample
that only one of its two uses needs.

Against synthetic input at 40 kHz, a channel fed a 4000-count square wave holds duty 100
and a channel fed 200 counts holds 100 as well, which is what a swing per channel is for;
a channel fed nothing at all holds 0. Dropping the first channel from 4000 counts to 300
drops it to 7, and it climbs back to 73 over the following nine seconds as its swing
decays two counts a frame towards the 410 floor. The floor is what bounds the gain: the
lower it is set the further a channel can recover, and the more room noise above the gate
is amplified with it. `text` is 15100 B, and the per-sample path inlines to a conversion
plus seven instructions per channel, roughly a quarter of the 25 µs; every call between
the four objects is inlined away and costs nothing.
