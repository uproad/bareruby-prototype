# The simulator, and what it answers

A host build is a real executable for the machine that compiled it, and it already runs
there. **The machine is that desk** — the entry says `machine: host` — and what the
executable has for its peripherals is a stub: a write to a pin prints what it was asked
and forgets it, a read answers zero, and a wait returns without any time having passed.

This gem runs that same executable a different way. The instructions are interpreted here
rather than executed by the desk, and every call the program makes into a peripheral is
caught before it reaches the stub and answered by an object instead. The object stays
after the call — so a pin knows what it is at, a port keeps what it sent, and a run that
has finished can be read.

That is the whole of what this is for. **A trace says a pin was written; a `Gpio` says
what the pin is.**

Two classes carry that between them, named for what they are:

| | |
| --- | --- |
| `Binding` | what a generated call arrives at. On a board that is C over an SDK; here it is Ruby over an interpreter |
| `Machine` | the desk, and the peripherals it carries |

```ruby
require "bareruby_prot/simulator"

run = BareRubyProt::Simulator.run("build/host/bareruby_program", seconds: 3)

run.machine.gpio(25).high?          # => true
run.machine.gpio(25).changes        # => 6
run.machine.uart(0).transmitted     # => "ready\r\n"
run.clock.ticks_ms                  # => 3000
```

## Starting a run

```ruby
BareRubyProt::Simulator.run(artifact, seconds: 3, out: $stdout, err: $stderr, input: nil) { |machine| }
```

| | |
| --- | --- |
| `artifact` | the executable a host build left, `build/<target>/bareruby_program` |
| `seconds:` | how much **virtual** time the program is given. A firmware never returns, so a run has to be told how long to watch — or told `nil`, and then it never ends, which is what watching a loop means |
| `out:` | where the program's own output goes — anything it `puts` |
| `err:` | where a panic goes |
| `input:` | an `IO` attached as the wire a serial port receives on, and as what an I2C read answers with. `$stdin` makes a run take its input the way the host build does |

A block given here is the one below under [driving the machine](#driving-the-machine-from-outside).
It answers a `Run`, already finished; `Simulator::Run.new(...)` builds the same thing
without starting it.

## Run

| | |
| --- | --- |
| `machine` | the `Machine` everything below is on |
| `clock` | the `Clock` this run kept time by |
| `status` | what the program exited with — 0 unless it panicked |
| `finished?` | whether the program ended by itself rather than running out of time |
| `instructions` | how many were interpreted — what the run cost |
| `start { \|machine\| }` | run it, when it was built rather than run. The block runs every time the program waits |

## Machine

The peripherals a program opened, filed under what it opened them as. Each reader answers
one when it is given a number and the whole table when it is not, so `machine.gpio` is
every pin the program touched and `machine.gpio(25)` is one of them.

| | |
| --- | --- |
| `gpio(pin = nil)` | by pin number |
| `uart(unit = nil)` | by unit |
| `pwm(pin = nil)` | by pin number |
| `adc(pin = nil)` | by pin number |
| `i2c(unit = nil)` | by unit |
| `onboard_led` | the indicator, once the program has opened one |
| `clock` | the same clock the run kept |
| `change(pin, level)` | move an input from outside, and deliver the interrupt if that is the edge somebody registered for |
| `while_waiting { \|machine\| }` | what to run every time the program waits (`Run#start` passes its block here) |

A peripheral the program never opened is not there yet: `machine.gpio(3)` is `nil` until
a `GPIO.new(3, ...)` has run, and `machine.onboard_led` is `nil` until an `OnboardLED` has
been. A machine has an indicator, but a program that never lights it has not met it.

### `snapshot`

The same readings as plain data, for a reader that is not Ruby: a display in another
process, a file, a check written elsewhere.

```ruby
machine.snapshot
# => { us: 500_000,
#      gpio: { 25 => { pin: 25, level: 1, changes: 6, direction: :out, pull: :none,
#                      open_drain: false, watching: false } },
#      uart: { 0 => { unit: 0, baudrate: 9600, ..., sent: "ready\\x0d\\x0a",
#                     pending: 0, waiting: "" } },
#      pwm: {}, adc: {}, i2c: {}, onboard_led: nil }
```

Every peripheral answers `snapshot` for itself, so one can be read alone. **Bytes come
back printable** — what is not a printable character is spelled `\xNN`, the way C spells
it — because what a port carries is bytes and not every byte is a character something
outside Ruby would take. Nothing here knows about JSON: turning this into bytes belongs to
whoever is doing the handing, and [`vscode/watch.rb`](../../vscode/watch.rb) is one that
does.

## Gpio

| | |
| --- | --- |
| `pin` | which pin |
| `level` | `0` or `1`, now |
| `level=` | set it, without delivering an interrupt — `Machine#change` is the one that does that |
| `high?` / `low?` | the same, asked as a question |
| `changes` | how many times it has changed. **A blink is visible in this without watching every write** |
| `direction` | `:in`, `:out` or `:high_z` |
| `pull` | `:up`, `:down` or `:none` |
| `open_drain?` | whether it was opened as one |
| `params` | the flags it was opened with, as the program spelled them |
| `events` / `handler` | what a registered interrupt is for, and where it is |

**A pulled-up pin starts high**, because that is what a pulled-up pin with nothing on it
reads. The stub in the host build answers zero for every pin instead, so a program that
reads an input is one of the places the two disagree.

## Uart

| | |
| --- | --- |
| `unit` | which port |
| `transmitted` | **everything it has sent**, as one string of bytes. Nothing here consumes it |
| `pending` | how many bytes have arrived and nobody has taken |
| `peek` | the next byte without taking it, or `nil` |
| `take` | the next byte, or `nil` |
| `receive(bytes)` | put bytes on the wire from outside |
| `clear_transmitted` / `clear_received` | empty either side |
| `baudrate`, `data_bits`, `stop_bits` | the frame, as it stands now — `setmode` moves these |
| `parity` | `:none`, `:even` or `:odd` |
| `flow_control?` | whether RTS/CTS was asked for |
| `txd_pin`, `rxd_pin`, `rts_pin`, `cts_pin` | the pins it was opened on, `-1` for a pin the program left to the machine |
| `line_ending` | what `puts` puts after a line, which the program can change |
| `breaks` | how many times a break has been sent |
| `events` / `handler` | the receive notification, if one was registered |
| `wire=` | the `IO` the queue fills from when nothing was put there directly |

The receive side is **one queue, and whoever asks first takes what is in it** — a handler
and a program calling `getbyte` are the same kind of consumer. The queue holds 256 bytes.

## Pwm

| | |
| --- | --- |
| `pin` / `slice` | which pin, and which slice it lands on |
| `frequency` | in whole hertz |
| `period_us` | the same setting, as a period |
| `duty` | 0 to 100 |
| `pulse_width_us` | the same setting, as a pulse width |

Both spellings of each pair are readable whichever one the program used, because a period
and a frequency are one setting asked for two ways.

## Adc

| | |
| --- | --- |
| `pin` / `channel` | which pin, and which channel that is |
| `raw` | what the next read will answer |
| `raw=` | set what it reads, from outside. `Adc::FULL` is full scale |
| `reads` | how many times the program has read it |

## I2c

| | |
| --- | --- |
| `unit` / `frequency` | which bus, and how fast |
| `written` | every transfer the program sent, each a `Transfer` with an `address` and its `bytes` |
| `answer_with(bytes)` | what the next reads answer |
| `wire=` | an `IO` to take those bytes from instead |

## OnboardLed

| | |
| --- | --- |
| `on?` | whether it is lit |
| `level` | `0` or `1` |
| `changes` | how many times it has changed |

## Clock

Nothing here reads the desk's clock. A wait moves virtual time by exactly what it was
asked to wait for, and **one instruction costs one microsecond**, which makes this a
one-megahertz machine. Both of those are the same on every desk, so two runs of one
artifact leave the machine in the same state — which is what lets it be something a check
is written against.

| | |
| --- | --- |
| `ticks_ms` | milliseconds since the run began, which is what the program reads too |
| `microseconds` | the same, unrounded |
| `seconds` | the same, as a float |
| `over?` | whether the run has had the time it was given. Always false when it was given none |

The instruction cost is also what ends a program that never waits: a loop that only
writes pins runs out of the time it was given rather than running until somebody stops
it.

## Driving the machine from outside

Nothing is attached to this machine but the caller, so an input only changes when it is
changed here — and **a wait is when that happens**. A block given to `start` runs every
time the program waits, holding the machine, which is the same moment hardware would
deliver an interrupt to a program. Before the program has run there is nothing to set up:
a peripheral does not exist until the program has opened it.

`samples/logger.rb` watches a pulled-up input and says over its serial port how many
times it has seen it pressed. Nothing is on the pin, so it reads high and the program
says nothing — until this presses it for a second:

```ruby
run = BareRubyProt::Simulator::Run.new("build/host/bareruby_program", seconds: 3)
run.start do |machine|
  machine.change(14, 0) if machine.clock.ticks_ms.between?(500, 1500)   # pressed
  machine.change(14, 1) if machine.clock.ticks_ms > 1500                # let go
end

run.machine.uart(0).transmitted   # => "logger ready\npressed: 1\n... pressed: 11\n"
run.machine.gpio(14).changes      # => 2
```

`Machine#change` runs a registered handler before it returns when the move is the edge it
was registered for. A receive notification is delivered inside the next wait that allows
one, because a handler runs in thread mode rather than in the interrupt — which is why
putting bytes on a wire in this block is enough to make one arrive.

## What a run does not have

- **No optimized build.** The frames are walked through saved base pointers, which every
  frame in a `-O0` build has. A build with an optimization level would need the call
  frame information read instead.
- **One receive depth.** A program that asks for a receive queue of its own size gets one
  in the build; here every queue holds 256 bytes.
- **No type comparison on a throw.** Every `catch` this compiler emits is a catch-all, so
  what is thrown is never asked what it is.
- **Nothing is attached to it.** A pin reads what it was last set to, an ADC reads what it was
  given, and a bus answers what it was told to answer. There is no device model behind
  any of them.
