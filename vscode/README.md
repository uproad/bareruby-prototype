# Watching a program run

The second half of the simulator: what the first half knows, shown to somebody.

The machine a host build runs on carries peripherals — pins that hold a level, ports that
keep what they sent, a clock that moves — and after a run they are all still there to be
read. This turns that into a panel: the pins as lamps, the serial ports as their buffers,
the square waves as their duty, and a slider along the run so any moment in it can be
looked at.

**A blink looks like a blink here.** The clock is virtual, so a three-second run finishes
in a fraction of a second and every frame of it arrives at once; the slider is what makes
that watchable rather than a single final state.

## What a project needs

**It watches a project, not this checkout.** Any project `bareruby new` wrote will do, and
the only thing it needs is the simulator in its bundle:

```ruby
# Gemfile
  gem "bareruby_prot-simulator"
```

`bundle install`, and the project is ready. Without it, `watch.rb` says so and stops —
nothing else here has to change, and no board has to be attached.

**Which project is worked out from the file in front of you**, by looking upward for a
Gemfile — the same question bundler answers, and the same root every verb reads its record
from. The folder the editor happens to have open is not it: somebody with their home
directory open is not working on their home directory.

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

It builds the program for the hosted entry, interprets what the build left, and writes
**one line of JSON every time the program waits** — which is every time the machine can
have changed. The last line is the run's end, marked `"over":true`. Nothing about those
lines is specific to an editor.

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

`package.sh` prints what it wrote, so the version never has to be typed. Then
**Developer: Reload Window** from the palette
(<kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>P</kbd>), open the project, and run **BareRuby:
Watch this program run**. It watches the `.rb` file in front of you, or `app/main.rb` when
that is not one. How much virtual time a run gets is `bareruby.seconds` in settings, 3 by
default.

**The extension carries `watch.rb` with it**, so once it is installed this checkout does
not have to be anywhere: the project's bundle is what the run reaches for.

**It asks a shell where `bundle` is**, once, and remembers. A desk that manages its Ruby
versions puts a shim on the path from a shell profile, and an editor started before any
profile was read has none of it — which arrives as `spawn bundle EACCES` rather than as
anything about Ruby.

**Changing `extension.js` needs the extension host restarted, not just the window
reloaded.** The panel is read off disk every time it opens, so the look changes on a
reload while the code behind it does not — which shows up as `{{program}}` in the title
and buttons that do nothing. **Developer: Restart Extension Host** is the shorter way;
reinstalling over the same version is not enough on its own.

While changing the extension itself, packing every time is not worth it — point VS Code at
the extension and at a project as two paths, and each new window is new code:

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
microsecond. `▶` plays, and playing means paying real time for virtual time — a wait worth
500 ms costs half a second at `1×` and a twentieth of one at `10×`. `□` holds, `⟩` takes
one step, `⟨` looks back at the frame before. The slider walks the whole run.

**Below the board**: what the serial ports carry, and then what the program printed, one
numbered line each.

A frame is a wait, so **a program that never waits leaves one frame**: everything happened
between the start and the end. `samples/blink.rb` leaves 7 over three virtual seconds,
`adc` 298.

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
