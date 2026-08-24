# Watching a program run

The second half of the simulator: what the first half knows, shown to somebody.

The machine a host build runs on carries peripherals — pins that hold a level, ports that
keep what they sent, a clock that moves — and after a run they are all still there to be
read. This turns that into a panel: the pins as lamps, the serial ports as their buffers,
the square waves as their duty, and a slider along the run so any moment in it can be
looked at.

**It does not end.** A firmware loops forever, and watching it do that is the point —
seeing a pin keep toggling, or stop toggling, is the whole of what this kind of debugging
is. The run stops when the panel is closed, or holds when somebody presses `□`.

**A blink looks like a blink.** Playing pays real time for virtual time, so a wait worth
500 ms takes half a second at `1×` and a twentieth of one at `10×`, and the slider looks
back over the last few thousand frames.

## What a project needs

**It watches a project, not this checkout.** Any project `bareruby new` wrote will do, and
the only thing it needs is the simulator in its bundle:

```ruby
# Gemfile
  gem "bareruby_prot-simulator"
```

`bundle install`, and the project is ready. Without it, `watch.rb` says so and stops —
nothing else here has to change, and no board has to be attached.

**Which project is worked out from the file in front of you** — any file, not only a
`.rb` — by looking upward for a Gemfile. That is the same question bundler answers and the
same root every verb reads its record from. The folder the editor happens to have open is
not it: somebody with their home directory open is not working on their home directory.
With a `.rb` in front of you that program is watched; with anything else, `app/main.rb`
is.

## Running it

Two halves, and the Ruby one is useful on its own. **Run it from the project**, because
the working directory is what says which `config/target.yml` is read and whose bundle the
gems come out of:

```sh
cd ~/ruby/bareruby-projects/test
bundle exec ruby ~/ruby/bareruby-prototype/vscode/watch.rb app/main.rb 3
{"ms":100,"gpio":{"25":{"pin":25,"level":0,"changes":1,...}},...}
{"ms":200,"gpio":{"25":{"pin":25,"level":1,"changes":2,...}},...}
```

It builds the program for the hosted entry, interprets what the build left, and writes a
line of JSON as it goes — **often enough to watch, and not tied to whether the program
ever waits**, so a loop with nothing but pin writes in it is as visible as a blink. With
no seconds named it runs until it is stopped; name some and it ends there, marked
`"over":true`. Nothing about those lines is specific to an editor.

A program that receives takes its bytes from a file named third:

```sh
bundle exec ruby .../vscode/watch.rb app/main.rb 3 input.txt
```

## In the editor

The extension is not published anywhere, so it is packed here and installed from the
file. **Under a remote connection it lands on the remote side**, which is where it has to
be: it starts a process in the project and reads the project's files.

```sh
code --install-extension "vscode/$(./vscode/package.sh)"
```

`package.sh` prints what it wrote, so the version never has to be typed. **Then close the
window and open it again** — see below; a reload is not enough. In the new window, open
the project and run **BareRuby: Watch this program run** from the palette
(<kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>P</kbd>). It watches the `.rb` file in front of
you, or `app/main.rb` when that is not one, and keeps running until the panel is closed.

**The extension carries `watch.rb` with it**, so once it is installed this checkout does
not have to be anywhere: the project's bundle is what the run reaches for.

**It asks a shell where `bundle` is**, once, and remembers. A desk that manages its Ruby
versions puts a shim on the path from a shell profile, and an editor started before any
profile was read has none of it — which arrives as `spawn bundle EACCES` rather than as
anything about Ruby.

**A newly installed extension needs the window closed and opened again.** Not
**Developer: Reload Window**, which keeps the extension host it already has, and not
**Developer: Restart Extension Host** either — under a remote connection neither has been
enough here. The panel itself is read off disk every time it opens, so **the look changes
while the code behind it does not**, which is a confusing way to be told nothing has
happened: `{{program}}` sits in the title and the buttons do nothing.

Because of that, packing and installing is the slow way round while the extension itself
is being changed. Point VS Code at the extension and at a project as two paths instead —
**each new window is new code**, with nothing to install and nothing to restart:

```sh
code --extensionDevelopmentPath=~/ruby/bareruby-prototype/vscode ~/ruby/bareruby-projects/test
```

## What the panel shows

**The machine, drawn as one.** A board stood on end, notched at the top, with the
indicator under the notch and fifty GPIO down its sides — 0 to 24 on the left, 49 down to
25 on the right, which is where a chip puts its numbers. Every pin is there whether or not
the program touched it.

**A pin says two things at once.**

| | |
| --- | --- |
| its **ring** | what it is being used as. Thin and grey when nothing has claimed it; thick and coloured once something has — green `GPIO OUT`, red `GPIO IN`, orange `ADC`, blue `DAC`, cyan `I2C`, violet `UART`, yellow `PWM` |
| its **fill** | what it is at. Black at nothing and green at everything, straight through the middle — so a digital pin is one or the other, and a duty cycle or a reading is somewhere between |

`ADC`, `DAC` and `PWM` put the figure itself outside the board, beside the pin: `1.83V`,
`50%`.

**The clock and the transport** sit to the right. The clock is virtual time to the
microsecond, and it keeps going. `▶` plays, and playing means paying real time for virtual
time — a wait worth 500 ms costs half a second at `1×` and a twentieth of one at `10×`.
`□` holds, `⟩` takes one step (one instruction), `⟨` looks back at the frame before. The
slider walks the last few thousand frames.

**Below the board**: what the serial ports carry, and then what the program printed, one
numbered line each.

**A program that never waits is watchable too.** Frames come out between instructions
rather than only at waits, so `samples/gpio_pico_loop.rb` — which writes twenty-six pins
and never sleeps — shows its pins moving, at 8,428 changes on GP0 in the first second.

If the run said anything on the way out — no simulator in the bundle, no `bundle` on the
path, a program that would not build — it is in a red box at the top instead of in a log.

**Two modes are reserved and reach no pin yet**, and the legend says so beside them.
`I2C` is opened by unit and answers with no pins at all — which is a hole in the class
rather than in this panel, and one that is being closed separately. `DAC` is a mode
nothing can reach going the other way. The colours are settled; what fills them is not
here yet.

## What is in here

| | |
| --- | --- |
| `watch.rb` | builds, interprets, and writes a frame per wait. The Ruby half |
| `extension.js` | starts that in the project and hands each line to a panel. Decides nothing about the machine |
| `media/panel.html` | the panel: the whole of what is drawn, and the slider |
| `package.json` | one command, one setting |
| `package.sh` | packs the five of them into a `.vsix` |

**There is no build step.** It is plain JavaScript, loaded as it is — a throwaway has no
business growing an npm toolchain, and nothing here is large enough to want one.

## What it does not do

- **It only watches.** The first half can move a pin (`machine.change`), answer an ADC and
  put bytes on a wire while a program runs, and none of that is wired to the panel yet.
  Doing it would make the channel a conversation rather than a stream, which is a step of
  its own.
- **The command feeds nothing.** `watch.rb` takes an input file, the palette command does
  not name one — so a program that waits on its serial port shows an empty queue when it
  is started that way.
- **It shows one run.** Starting the command again opens another panel; there is nothing
  that compares two.
- **Bytes are shown printable.** What a port sent is rendered with `\xNN` for anything
  that is not a printable character, which is what makes it a string a panel can hold.
