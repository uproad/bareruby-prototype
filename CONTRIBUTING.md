# Contributing

This is a throwaway feasibility prototype, so what counts as a good change here is not
what would count in the compiler it is standing in for. There are no tests, no
diagnostics and no error handling, and a change is finished when a sample program that
could not be compiled before can be. [`AGENTS.md`](AGENTS.md) states the discipline in
full; this file says how the thing is put together and how to build, install and check a
change to it.

## How the repository is laid out

```text
bareruby                  the entrance while working in the checkout
ref.rb                    the default program `bareruby compile` takes
samples/                  the programs each milestone was proved with
reserved/                 notes for bindings that do not exist yet — ESP-IDF, UEFI, WASI
config/                   target.yml.sample, and target.yml if this desk made one
gems/
├── bareruby_prot-compiler/          the first stage: every pass, the IRs, the runtime
├── bareruby_prot/                   everything after it: the executable, target.yml, flashing
├── bareruby_prot-binding-*/         pico_sdk, arduino, stm32cube
└── bareruby_prot-stdlib-*/          gpio, pwm, adc, uart, i2c, onboard_led
```

**A gem is a build, not a checkout**: editing one changes nothing until it has been built
and installed again. That is the whole difference between `gems/` and the rest of this
repository, and the first thing to know before changing anything in it.

## The two halves of the tool

| gem | what it is | what it holds |
| --- | --- | --- |
| `bareruby_prot-compiler` | the first stage | every pass, the intermediate representations, the language runtime, the vocabulary a composition is spelled in, and the one binding that needs no hardware |
| `bareruby_prot` | everything after it | the one executable, what a desk is (`target.yml`), `target add`, starting a second stage, flashing |

The line between them is the line between the two stages. Breaking it means reaching
across a gem boundary rather than typing a relative path: it can still be done, but it
cannot be done quietly.

**What crosses that line is a binding, never the compiler.** A binding is written in the
words of what it calls on one side and starts a second stage on the other, so the gem that
carries one carries both dependencies — which is why the compiler gem can only carry a
binding that has no second stage of its own to start. The one that needs no hardware is
carried there for that reason rather than by privilege: the moment it reached for the half
that runs a second stage, the two gems depended on each other, and the first stage stopped
being loadable on its own.

`./bareruby` at the top is not the command. It reads the two gems out of the working tree,
adds `.gems/` as a place to look, and then runs the executable the ecosystem gem ships, so
that a checkout cannot drift from what a user gets.

Everything either half reaches for is found **from the project root** rather than from
beside its own source — `build/`, `dump/`, `config/target.yml` and the default `ref.rb`.
Where that root is, is [bundler's answer](#where-a-project-starts).

## Where the shipped C++ comes from

Most of the C++ that lands in `build/` is carried by this repository rather than written
line by line by the compiler, and where a piece of it lives says who it belongs to.

What is the same everywhere belongs to the last pass and sits beside it in
`lib/bareruby_prot/pass/pass_12_cpp_source_generator/` inside the compiler gem: the runtime
proper — the arena, the strings, the fixed-point arithmetic — and the declarations every
binding answers.

What differs by what is being called sits in one directory per binding,
`lib/bareruby_prot/binding/<binding>/` inside whichever gem carries it: `binding.rb`
implements those declarations in its own words, `build.rb` writes down what the second
stage is, `toolchain.rb` runs it, and `flash.rb` puts the result on a machine. Each names
its own translation units, because the name a piece of C++ is written under belongs with
that C++ and nowhere else.

**`toolchain.rb` is the one of those that a binding may leave out.** What to run and what
that run leaves behind are already in the manifest `build.rb` wrote, and reading those two
lines back is the ecosystem's own work rather than any machine's — so a binding with
nothing to add around them declares no toolchain, and the default answers for it. A
binding writes one when it has something of its own to say: paths an SDK has to be told
before it will run, sources to gather where a build system expects them, images to bring
up out of a tree the build left. The one that needs no hardware has none of that, and one
`g++` line is the whole of its second stage.

**Nothing outside that directory knows the binding is there.** Two more files finish it —
`targets.rb`, which registers the machines it reaches and the compositions it can produce
for them, and `family.yml`, which says how `target add` should offer them — and with those
six the compiler names no binding at all. It finds them by looking, in every gem installed
at the desk, under one path. **The binding that needs no hardware is found the same way as
the rest**, because the compiler is a gem too and beside itself *is* where a gem lives.

Two consequences are worth knowing:

- **Looking in every gem means looking in copies of one.** A checkout that carries a gem
  in its working tree and has the same gem installed finds the same binding twice, and
  loading both redefines every constant in it. A binding is identified by the name of the
  directory its declaration sits in, and the first one found wins; the load path is
  searched before the installed gems, so a working tree beats a copy of itself.
  **A standard class answers the same question with the name of its file**, because that
  is the shape it comes in — one class, one file, in a directory it shares with the
  others. Loading them in name order after that is what keeps the answer the same
  wherever the copies were found.
- **`target.yml` records a composition, not a gem**, so uninstalling a binding a recorded
  target names leaves that record pointing at nothing. The run stops and says which
  composition went missing, and every other target builds once the entry is removed or
  the gem is back.

`main.cpp`, the one C++ file that is written rather than carried, is rendered from the
low-level IR; the binding it is built for supplies the entry point and says whether output
has anywhere to go — and for a machine whose `main` is owned by someone else, the file is
called `bareruby_program.cpp` instead, because this side does not name an entry point it
does not own.

## Where a machine's own facts live

The four Pico boards share one pico-sdk binding and differ only in the two words their
generated `CMakeLists.txt` hands to the SDK. Those two words are pico-sdk's, not the
boards': `PICO_BOARD` is what that SDK calls a board, and `PICO_PLATFORM` is not even the
chip's name, since an RP2350 answers to `rp2350-arm-s` or `rp2350-riscv`. So they are kept
where the machine and the binding meet rather than on the machine:

```ruby
# gems/bareruby_prot-binding-pico_sdk/lib/bareruby_prot/binding/pico_sdk/machine/pico2_w.rb
def self.pico_board = "pico2_w"

def self.pico_platform = "rp2350"
```

What is left on the board itself is what is true of it whoever asks — the key it is known
by, and the chip it carries.

## A class the language offers, from a gem

**`I2C` is not a class this compiler knows.** What may be said to a bus, what those calls
lower to, what the generated header must declare, and which translation unit a binding has
to supply once it is reached — all four arrive from `gems/bareruby_prot-stdlib-i2c/`, and
nothing on this side mentions I2C. Uninstall it and `samples/i2c.rb` no longer compiles,
the header no longer declares `bareruby_i2c_t`, and **everything else compiles exactly as
it did**.

The part worth keeping is how a peripheral and a binding agree without knowing each other.
The peripheral names its own C functions and asks for a unit by a key of its own choosing;
the binding says which file answers that key. Neither names the other, and the compiler
holds neither list:

```ruby
units: { i2c: %i[bareruby_i2c_init bareruby_i2c_write bareruby_i2c_read],
         i2c_read: %i[bareruby_i2c_read] }        # what the peripheral asks for

UNITS = { i2c: I2C_FILE, i2c_read: I2C_READ_FILE } # what the binding answers
```

Both gems have to be installed for a program that uses a bus on a board to build, and they
meet only in the generated C++. A peripheral that can be uninstalled cannot share a
translation unit with one that cannot — remove the declarations and an implementation is
left with nothing to implement against — so each binding carries each peripheral in a unit
of its own, asked for by that same key.

Five cases the six installed classes cover between them:

- **A block can be declared.** `GPIO#on_interrupt` takes a zero-argument block and turns
  it into a function running in the realtime context. The handler, the context and the
  checks over it are the language's and stay here; what the gem declares is only that this
  method's block becomes one. One kind of block is declarable, because one kind exists.

  ```ruby
  on_interrupt: { function: :bareruby_gpio_on_interrupt, parameter_types: %i[Int32],
                  keywords: { edge: 0 }, block: :realtime_handler }
  ```

- **A call that answers a variable-length string is handed somewhere to put it.** The
  declared return type is the whole of what says so — `read` and `gets` on a serial line
  answer `:arena_string`, and the region reaches the binding as an argument the program
  never wrote. Nothing here recognises a class by name to decide it.

- **A call can send whatever the program had as one sequence of bytes.** `payload_from`
  says where those arguments begin, and everything from there on — integers, strings,
  arrays, a string built in a region — is gathered into one string first, so the binding
  is handed one pointer and one length. One call in Ruby is one transaction on the wire.

  ```ruby
  write: { function: :bareruby_i2c_write, parameter_types: [], return_type: :Int32,
           payload_from: 1 }        # everything after the address is the payload
  ```

- **A binding need not implement a peripheral at all.** A NUCLEO board reached through the
  STM32Cube HAL has no PWM, and says so by having no file for that key. What would have
  been a link error at the second stage is a refusal at the first.
- **A unit's file can be the machine's decision.** `OnboardLED` has no single file to ask
  for, because the same indicator is a pin on one board and a radio on another, so the key
  resolves to a question: the binding answers `:onboard_led` by asking the cell where that
  machine and it meet. Nothing about the mechanism is specific to indicators.

With all six out, **the compiler holds no peripheral at all.** `Peripheral` is a registry
with nothing registered in it until a gem arrives. Uninstall every one and the compiler
still builds any program that keeps to the language — integers, classes, arrays, strings,
arenas, `puts`, `sleep`. What it can no longer do is name a piece of hardware, because
nothing installed has told it that hardware exists.

## What a build reaches for, and who brings it

**Which SDK and cross compiler a board needs is the binding's answer; where they go and
how they are brought down is this side's.** The ecosystem never learns what pico-sdk is —
it knows how to verify an archive against a hash and how to clone a repository at a
commit, and a binding that needs neither does not use it.

The lock beside the binding is the whole of what is known:

```yaml
arm_gcc:
  from: https://developer.arm.com/-/media/Files/downloads/gnu/13.2.rel1/binrel
  directory: common/arm/arm-gnu-toolchain-13.2.Rel1-x86_64-arm-none-eabi
  archives:
    linux-x64:
      file: arm-gnu-toolchain-13.2.rel1-x86_64-arm-none-eabi.tar.xz
      sha256: 6cd1bbc1d9ae57312bcd169ae283153a9572bd6a8e4eeae2fedfbc33b115fdbb
sdk:
  github: raspberrypi/pico-sdk
  tag: 2.3.0
  commit: 98a542c1a62fb549ffb5d66a3e5892b06276b670
  submodules:
    lib/tinyusb: 86ad6e56c1700e85f1c5678607a762cfe3aa2f47
    lib/cyw43-driver: 055d64274b014dd7b1c2fc94d26e8a18face7124
```

Nothing says `latest`. The archive is pinned by release and SHA-256 and the hash is not
optional — what is being unpacked is a compiler, and it came off the network. The
repository is pinned by tag *and* commit, because a tag that has been moved is the failure
a tag alone cannot see, and its submodules by commit, because a submodule moved underneath
a release is a different SDK with the same name.

Two of the SDK's five submodules are taken. btstack, lwip and mbedtls are a Bluetooth and
networking stack this compiler has no way to ask for, and they are most of what a full
checkout weighs: **75 MB against the 129 MB a plain `git clone --recursive` leaves**.

Three properties a build depends on:

- **A desk that already has one says so, and nothing is fetched.** `PICO_SDK_PATH` and
  `PICO_TOOLCHAIN_PATH` still win, and then the store is not even created. Which variable
  covers which thing is known in the binding and nowhere else, which is why the skipping
  lives there rather than in the fetching.
- **The second run is silent and touches no network.** This runs underneath every build; a
  check that reached out would make every build pay for the first one's convenience.
- **It says what it is taking before it takes it.** A gigabyte should not start in silence.

## Where a project starts

**Where the root is, is bundler's answer.** A project names the ecosystem in its Gemfile
and runs it through the binstub beside it, so by the time the executable is running,
something has already had to find the Gemfile. The process is stood at that root before
the compiler is even loaded — a gem that knows nothing about projects needs to be told
nothing if it is standing in the right place. Nothing walks a tree looking for a marker,
which matters precisely because the file worth finding, `config/target.yml`, is the file
allowed to be missing: **a run that cannot find the root does not get as far as reading a
record.**

This checkout has a `Gemfile` of its own for that reason and no other: it runs its own
commands, so it needs to be a root the same way a generated project is.

The template is files rather than strings, so what a user gets can be read as what it will
be — and files are exactly what a `spec.files` can leave behind. The dot file is shipped
as `gitignore` and renamed on the way out, because under its own name it would take effect
here and hide the very files it is meant to carry. Two things in it cannot be the same on
two desks and are written when the project is: which machine is doing the compiling, and
where the gems come from. The second is a prototype's problem only, since nothing here is
published.

## How `target add` decides what to ask

A composition is three answers rather than one, and that is only visible when all three
are in view as a single choice fills them in. **A field is settled the moment every
candidate still in play agrees on it**: every machine in a pico-sdk family is reached
through pico-sdk, so the binding is answered before any machine is named. A family holding
one machine settles all three at once. It is a count of what the answers still allow rather
than a rule about families — a family reached two ways stops settling a binding, with
nothing here to change.

Families stand to the left of the machines they hold, and moving right steps into them.
**Choosing a family is a move rather than an answer**: it names no field of the entry, so
answering it would be a transition that settles nothing.

What a family needs beyond the three — the path to a CubeMX project, how to optimize the
build — is in that family's own `family.yml`, beside the binding that can build it, so a
machine that does not exist yet is reached by adding a binding rather than by editing a
list. It restates no composition: a family names targets, and their machine, binding and
triple come from the binding's `targets.rb`, where they already are.

## Building and installing the gems

`./bareruby` reads the two tool gems out of the working tree, so an edit to a pass takes
effect at once. The add-on gems do not work that way — a binding or a standard class is
found by looking through installed gems, so it has to be installed before the compiler can
see it.

```sh
for g in gems/*/; do (cd $g && gem build *.gemspec -o /tmp/$(basename $g).gem); done
GEM_HOME=$PWD/.gems gem install --local --no-document /tmp/bareruby_prot*.gem
```

`.gems/` is gitignored and sits under the repository for the same reason `.tools/` does. A
desk that installs them the ordinary way is served as well; this only adds a place to
look.

Run at least once wholly from installed gems, with nothing of the working tree on the
path. It is the only check that catches a `spec.files` that misses a file — nothing
running from the working tree can:

```sh
GEM_HOME=$PWD/.gems .gems/bin/bareruby build samples/heartbeat.rb --target=mega
```

## Checking a change

There is no test suite. What stands in for one is a sample program that fails to compile
before the change and compiles after it, plus evidence that nothing else moved.

1. **Write the sample first.** Put it in `samples/`, and check that
   `./bareruby compile samples/<topic>.rb` **fails** on the current code. A sample that
   already compiles is verifying nothing.
2. **Run it.** `./bareruby build --target=host samples/<topic>.rb`, then run the
   executable: fd1 is `puts` and fd2 is the peripheral call trace. A sample that needs
   input takes it on stdin.
3. **Regression.** Every other program in `samples/`, and `ref.rb`, still compiles.
4. **Determinism.** Compile the same program twice and compare hashes across `dump/` and
   `.bareruby/`. They must match — which also confirms that each pass boundary can be
   reloaded from its own dump.
5. **Board build.** `./bareruby build --target=<board>` through to the `.uf2`, `.hex` or
   ELF, and record `text`, `bss` and artifact size per board in
   [`HISTORY.md`](HISTORY.md). Where `--no-exceptions` changes the answer, measure both.
6. **Hardware.** Flashing needs the board in front of someone. Ask rather than assume, and
   **never write "verified" for something that was only built** — say "built but not
   hardware-flashed".

## Recording it

The value of this repository is the record of what ran and what it cost, so a change that
proves something is not finished until it is written down.

- [`HISTORY.md`](HISTORY.md) — what the change proved, what it deliberately did not
  implement, and the measured cost.
- [`samples/README.md`](samples/README.md) — one row for the new sample, saying what it
  covers.
- [`README.md`](README.md) — only if what a user types or sees has changed.
