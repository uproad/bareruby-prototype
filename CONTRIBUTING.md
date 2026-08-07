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
reserved/                 notes for bindings that do not exist yet
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

## The compiler and the ecosystem, from two gems

There is nothing left at the top of this repository that runs. Everything that does is a
gem under `gems/`, and the two that are not add-ons are the two halves of the tool itself:

| gem | what it is | what it holds |
| --- | --- | --- |
| `bareruby_prot-compiler` | the first stage | every pass, the intermediate representations, the language runtime, the vocabulary a composition is spelled in, and the one binding that needs no hardware |
| `bareruby_prot` | everything after it | the one executable, what a desk is (`target.yml`), `target add`, starting a second stage, flashing |

The line between them is the line between the two stages. **That was already the rule, and
it was already being kept — what changed is that breaking it now means reaching across a
gem boundary rather than typing a relative path.** It can still be done. It cannot be done
quietly.

`./bareruby` at the top is not the command. It reads the two gems out of the working tree,
adds `.gems/` as a place to look, and then runs the executable the ecosystem gem ships, so
that a checkout cannot drift from what a user gets.

Running wholly from installed gems is the same commands through a binstub, and produces
the same artifacts. This is also the only check that catches a `spec.files` that misses a
file — nothing that runs from the working tree can:

```sh
(cd gems/bareruby_prot-compiler && gem build *.gemspec &&
 GEM_HOME=../../.gems gem install --local bareruby_prot-compiler-0.0.1.gem)
(cd gems/bareruby_prot && gem build *.gemspec &&
 GEM_HOME=../../.gems gem install --local bareruby_prot-0.0.1.gem)

GEM_HOME=$PWD/.gems .gems/bin/bareruby build samples/heartbeat.rb --target=mega
```

**What each side reached for by knowing where it was.** The pattern the bindings found
turned out to be the whole story here too, and every remaining case was the same mistake:

- `build/` and `dump/`, the compiler's own output, were found beside `compiler.rb`. A
  compiler that is a gem would have written a program's C++ into the installed gem.
- `target.yml`, the desk's record, was found beside `deployment.rb`. This one is worth
  dwelling on: a gem looking beside itself finds no file, and *no file is the ordinary
  case*. So nothing failed. `bareruby build --target=arduino-mega2560` exited zero and put
  its artifact under the composition's name instead of the name the desk had given it,
  and only a byte-comparison against the previous build caught it. **A path that is wrong
  is loud; a path that is wrong where an empty answer is legal is silent.**
- `ref.rb`, the default source, was found beside the executable.

All three are found from the project root now, which is what they always meant. Where that
root is, is [further down](#where-a-project-starts).

**Looking in every gem means looking in copies of one.** A checkout that carries a gem in
its working tree and has the same gem installed finds the same binding twice, and loading
both redefines every constant in it — `host` did exactly this the moment the compiler
became a gem that could also be installed. A binding is identified by the name of the
directory its declaration sits in, and the first one found wins; the load path is searched
before the installed gems, so a working tree beats a copy of itself.

**Which bindings there are is asked once.** `target add` used to glob for `family.yml` on
its own, which meant two searches that had to agree about what a binding is and where one
may live. The compiler already answers that question, so the family a binding offers is
read from beside the declaration it answered with.

Nothing about a build changed. `samples/heartbeat.rb` produces the same `.hex` on the Mega
2560 and the same ELF on the NUCLEO as before either gem existed, whether built from the
working tree or from `.gems/bin/bareruby` with nothing but installed gems on the path.

`reserved/` holds the notes for three bindings that do not exist yet — ESP-IDF, UEFI and
WASI. They were filed under a binding directory that no longer has anywhere to be.

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

**Nothing outside that directory knows the binding is there.** Two more files finish it —
`targets.rb`, which registers the machines it reaches and the compositions it can produce
for them, and `family.yml`, which says how `target add` should offer them — and with those
six the compiler names no binding at all. It finds them by looking, in every gem installed
at the desk, under one path. **The binding that needs no hardware is found the same way as
the rest**, because the compiler is a gem too and beside itself *is* where a gem lives.

`gems/bareruby_prot-binding-pico_sdk/`, `gems/bareruby_prot-binding-arduino/` and
`gems/bareruby_prot-binding-stm32cube/` are three that have left. They are gems, built and
installed like any other, and the machines they reach arrive with them — four Raspberry Pi
Pico boards from the first, `arduino-mega2560` from the second, `stm32-nucleo-f446re` from
the third:

```sh
cd gems/bareruby_prot-binding-pico_sdk
gem build bareruby_prot-binding-pico_sdk.gemspec
GEM_HOME=../../.gems gem install --local bareruby_prot-binding-pico_sdk-0.0.1.gem
```

`.gems/` sits under the repository for the same reason `.tools/` does, and is gitignored
for the same reason too. A desk that installs them the ordinary way is served as well;
this only adds a place to look. **Uninstall one and its machines are gone from
`target list`, while everything else still compiles** — which is what an add-on being an
add-on means.

Packaging the first asked two questions that a single tree never had to answer.

**Where the SDK is.** `toolchain.rb` reached for `.tools/` by walking up out of its own
directory, which works only while it is part of the checkout. It is found from where the
command was run instead. An SDK is a gigabyte of somebody else's release; it belongs to
the desk, not to the gem that asks for it.

**What the compiler owes a binding.** Every binding reached the shared second-stage runner
with a relative path. Once one is packaged elsewhere that path leads nowhere, and **what
was a convenience becomes an interface**: it is published under `bareruby_prot/` now and
is required by name. Nothing else crossed that line — one file was the whole of what a
binding needs from this side.

**Packaging the second asked neither of them again.** One line of the Arduino binding
changed — the same `.tools/` walk, corrected the same way — and the interface the first
one established held with nothing added to it. The rest is a directory move: the
`arduino-mega2560` build comes out byte for byte identical, 2702 B of flash and 186 B of
RAM for `samples/heartbeat.rb` and the same `.hex`. That is worth stating because the two
bindings do not resemble each other. This one's second stage is not a file list but a
sketch directory that `toolchain.rb` gathers, and its board is written to over a serial
port `flash.rb` asks `arduino-cli` to identify. Neither arrangement needed anything of
the compiler that the first had not already asked for.

**The third found the other half of the first question.** `.tools/` was one thing a
binding had been reaching for by walking up out of its own directory; the STM32Cube bridge
reached for a second, and it is not the desk's — `cube.sh` picked up the generated headers
from `build/` at the top of the checkout, which is the *first stage's output from this very
run*. A gem cannot walk up to that either. They are found from the target's own directory
now, one level up, which is the same place the source list already reaches the shared
translation units at. **The correction is not a workaround: a build should find what it
produced from what it produced, and reaching the checkout root for it was only ever
right by accident.**

The NUCLEO build comes out byte for byte identical across the move — 5416 B of text and
1644 B of bss for `samples/heartbeat.rb`, the same ELF — and this is the binding with the
most to travel: a bash bridge that synchronizes into a project this repository does not
own, a header that project includes, and the two prose files that say how to prepare it.
All of them are in the gem, because a desk that installs this binding cannot use it until
it has read them.

One edge is worth knowing. `target.yml` records a composition, not a gem, so uninstalling
a binding a recorded target names leaves that record pointing at nothing. The run stops
and says which composition went missing, and every other target builds once the entry is
removed or the gem is back.

## Where a machine's own facts live

The four Pico boards share one pico-sdk binding and differ only in the two words their
generated `CMakeLists.txt` hands to the SDK, and where those two words are kept is the
general answer to where a fact about a board belongs.

Those two words are pico-sdk's, not the boards'. `PICO_BOARD` is what that SDK calls a
board, and `PICO_PLATFORM` is not even the chip's name: an RP2350 answers to
`rp2350-arm-s` or `rp2350-riscv` once which of its two instruction sets to build for is
chosen. So they are kept where the machine and the binding meet rather than on the machine:

```ruby
# gems/bareruby_prot-binding-pico_sdk/lib/bareruby_prot/binding/pico_sdk/machine/pico2_w.rb
def self.pico_board = "pico2_w"

def self.pico_platform = "rp2350"
```

What is left on the board itself is what is true of it whoever asks — the key it is known
by, and the chip it carries.

## A class the language offers, from a gem

`gems/bareruby_prot-stdlib-i2c/` is the other half of the same idea. **`I2C` is not a
class this compiler knows.** What may be said to a bus, what those calls lower to, what
the generated header must declare, and which translation unit a binding has to supply once
it is reached — all four arrive from the gem, and nothing on this side mentions I2C.

```sh
cd gems/bareruby_prot-stdlib-i2c
gem build bareruby_prot-stdlib-i2c.gemspec
GEM_HOME=../../.gems gem install --local bareruby_prot-stdlib-i2c-0.0.1.gem
```

Uninstall it and `samples/i2c.rb` no longer compiles, the header no longer declares
`bareruby_i2c_t`, and **everything else compiles exactly as it did**.

The part worth keeping is how a peripheral and a binding agree without knowing each other.
The peripheral names its own C functions and asks for a unit by a key of its own choosing;
the binding says which file answers that key. Neither names the other, and the compiler
holds neither list:

```ruby
units: { i2c: %i[bareruby_i2c_init bareruby_i2c_write bareruby_i2c_read],
         i2c_read: %i[bareruby_i2c_read] }        # what the peripheral asks for

UNITS = { i2c: I2C_FILE, i2c_read: I2C_READ_FILE } # what the binding answers
```

**Both gems have to be installed for a program that uses a bus on a board to build**, and
they meet only in the generated C++. `samples/i2c.rb` for `raspberry-pi-pico` is 49568 B
of text and a 118272 B `.uf2`, built from a declaration in one gem and an implementation
in another.

A gem is a build, not a checkout: **editing one changes nothing until it is built and
installed again.** That is the whole difference between the two halves of `gems/` and the
rest of this repository.

`GPIO` left the same way, and cost two things I2C had not.

**A block had to be declarable.** `GPIO#on_interrupt` takes a zero-argument block and turns
it into a function running in the realtime context, and the compiler used to find that by
looking for this class and this method **by name**, in two passes. The handler, the context
and the checks over it are the language's and stay here; what is declared is only that this
method's block becomes one:

```ruby
on_interrupt: { function: :bareruby_gpio_on_interrupt, parameter_types: %i[Int32],
                keywords: { edge: 0 }, block: :realtime_handler }
```

One kind of block is declarable, because one kind exists. A second arrives with the second
method that needs it.

**Every binding's C++ had to be split.** `gpio`, `pwm`, `uart` and `adc` shared one
translation unit that was always linked. **A peripheral that can be uninstalled cannot
share a file with one that cannot** — remove the declarations and an implementation is left
with nothing to implement against. Each binding now carries GPIO in a unit of its own, asked
for by the same key mechanism I2C uses.

That split is not only about removability. `samples/heartbeat.rb` lights the on-board LED
and never touches a pin, and on the Mega 2560 it fell from **4190 B of flash to 3496 B**:
694 B that were being linked for a class the program does not name. The Pico builds are
unchanged, where `--gc-sections` was already dropping it.

`PWM` followed, and answered a question the first two had not raised: **a binding need not
implement a peripheral at all.** A NUCLEO board reached through the STM32Cube HAL has no
PWM, and now says so by having no file for that key rather than by an entry leading
nowhere. What used to be a link error at the second stage is a refusal at the first.

`UART` was the one that took two units rather than one — sending and receiving, because
receiving answers a variable-length string and reaches the arena to do it. It also carried
two things off that the compiler had been holding on its behalf: **which calls answer a
variable-length string** (read off the declared return types now, rather than a list of
function names), and **where a printf expansion's variable arguments begin** (a fact about
that function's signature, so the function's own declaration says it).

`ADC` went the same way, and needed nothing new: a table, a declaration, one unit. **That
is the point at which the road was finished** — the third class through it asked no
question the first two had not already answered.

The Mega 2560 kept getting smaller as each class left the always-linked file:
`samples/heartbeat.rb` went 4190 B → 3496 B → **2702 B of flash**, and 657 B → **186 B of
SRAM** once `Serial` stopped being linked into a program that never prints. Roughly a third
of the original build was machinery for classes the program does not name.

`OnboardLED` went last and was the one that did not fit. Every other class asks a binding
for a file; this one has no single file to ask for, because the same indicator is a pin on
one board and a radio on another. **So the key resolves to a question rather than a name**
— the binding answers `:onboard_led` by asking the cell where that machine and it meet, and
that cell was already there, saying which C++ this board's LED needs and which library it
drags in. Nothing about the mechanism is specific to indicators: a unit whose file the
machine decides is now expressible, and this is the first one.

With it gone, **the compiler holds no peripheral at all.** `Peripheral` went from 156 lines
to 93 and is a registry with nothing registered in it until a gem arrives:

```
bareruby_prot-stdlib-gpio     bareruby_prot-stdlib-pwm    bareruby_prot-stdlib-adc
bareruby_prot-stdlib-uart     bareruby_prot-stdlib-i2c    bareruby_prot-stdlib-onboard_led
```

Uninstall all six and the compiler still builds every program that keeps to the language —
integers, classes, arrays, strings, arenas, `puts`, `sleep`. What it can no longer do is
name a piece of hardware, because nothing installed has told it that hardware exists.

`main.cpp`, the one C++ file that is written rather than carried, is rendered from the
low-level IR; the binding it is built for supplies the entry point and says whether output has
anywhere to go — and for a machine whose `main` is owned by someone else, the file is
called `bareruby_program.cpp` instead, because this side does not name an entry point it
does not own.

What is left of the pass is the assembly: it asks the low-level IR what the program
reaches for, asks each source for its files, and hands each target the ones it needs. All
of it was one file until the C++ grew to two thirds of it, which is a poor place to read
any of it from.

## What a build is made of, and who brings it

An SDK and a cross compiler are gigabytes of somebody else's release. **Which ones a board
needs is the binding's answer; where they go and how the two shapes they come in are
brought down is this side's.** The ecosystem never learns what pico-sdk is — it knows how
to verify an archive against a hash and how to clone a repository at a commit, and a
binding that needs neither does not use it. `arduino-cli` installs its own cores, and
there is nothing here for it to fit into.

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

Three properties are worth stating because a build depends on them:

- **A desk that already has one says so, and nothing is fetched.** `PICO_SDK_PATH` and
  `PICO_TOOLCHAIN_PATH` still win, and then the store is not even created. Which variable
  covers which thing is known in the binding and nowhere else, which is why the skipping
  lives there rather than in the fetching.
- **The second run is silent and touches no network.** This runs underneath every build; a
  check that reached out would make every build pay for the first one's convenience. The
  question "is it already here" is answered from the disk.
- **It says what it is taking before it takes it.** A gigabyte should not start in silence.

The move from the project's `.tools/` to the desk's store changes nothing that reaches a
board. `samples/heartbeat.rb` built for the Pico both ways gives **the same `.uf2`, byte
for byte**, the same 30324 B of text and 3604 B of bss, and the same ELF once stripped.
The unstripped ELFs differ, and only there: debug information records where the SDK it was
compiled against was sitting.

## Where a project starts

**Where the root is, is bundler's answer.** A project names the ecosystem in its Gemfile
and runs it through the binstub beside it, so by the time the executable is running,
something has already had to find the Gemfile. `config/target.yml`, the source compiled
when none is named, `build/` and `dump/` are all found from there, and the process is
stood at the root before the compiler is even loaded — a gem that knows nothing about
projects needs to be told nothing if it is standing in the right place.

That answers the silent failure the move to gems turned up. **A run that cannot find the
root does not get as far as reading a record**, so a desk that has recorded nothing and a
run that has lost its way stop being the same silence. Nothing here walks a tree looking
for a marker, and nothing had to decide what would count as one — which matters precisely
because the file worth finding is the file allowed to be missing.

This checkout has a `Gemfile` of its own for that reason, and for no other: it runs its own
commands, so it needs to be a root the same way a generated project is.

Two things in the template cannot be the same on two desks and are written when the project
is: which machine is doing the compiling, and where the gems come from. The second is a
prototype's problem only — nothing here is published, so a project reads these gems from
the checkout or the GEM_HOME it was made from, where a released one would name a version.

Running it wholly from installed gems produces the same firmware, byte for byte:

```sh
for g in gems/*/; do (cd $g && gem build *.gemspec -o /tmp/$(basename $g).gem); done
GEM_HOME=/tmp/gh gem install --local --no-document /tmp/*.gem
GEM_HOME=/tmp/gh PATH=/tmp/gh/bin:$PATH bareruby new /tmp/installed
```

The template is files rather than strings, so what a user gets can be read as what it will
be — and files are exactly what a `spec.files` can leave behind. Nothing requires them, so
nothing in this repository would notice them missing; the project would simply come out
empty, and only an install-and-run says so. The dot file is shipped as `gitignore` and
renamed on the way out, because under its own name it would take effect here and hide the
very files it is meant to carry.

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

None of what it asks is anything to look up, which is why it is asked for instead. Every
entry has a machine, a name and a debug build, so those are asked by the command itself.
What else a family needs — the path to a CubeMX project, how to optimize the build — is in
that family's own `family.yml`, beside the binding that can build it, so a machine that
does not exist yet is reached by adding a binding rather than by editing a list. It
restates no composition: a family names targets, and their machine, binding and triple
come from the binding's `targets.rb`, where they already are. The machine that needs no
hardware is offered first and the rest are alphabetical, so anything attaching later has
one obvious place to go.

## Building and installing the gems

`./bareruby` at the top of the checkout reads the two tool gems out of the working tree
and adds `.gems/` as a place to look, so an edit to a pass takes effect at once. The
add-on gems do not work that way — a binding or a standard class is found by looking
through installed gems, so it has to be installed before the compiler can see it.

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
   input takes it on stdin — `printf 'OK' | ./build/host/bareruby_program`.
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
