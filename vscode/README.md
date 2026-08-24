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

The extension is not published anywhere, so it is loaded from where it sits. **Point VS
Code at the extension and at the project separately** — they are different directories:

```sh
code --extensionDevelopmentPath=~/ruby/bareruby-prototype/vscode ~/ruby/bareruby-projects/test
```

In that window, run **BareRuby: Watch this program run** from the command palette
(<kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>P</kbd>). It watches the `.rb` file in front of
you, or `app/main.rb` when that is not one. How much virtual time a run gets is
`bareruby.seconds` in settings, 3 by default.

The other way is <kbd>F5</kbd>: open `bareruby-prototype/vscode` itself in VS Code and
press it. That opens an Extension Development Host with **no folder**, so open the project
in it before running the command.

## What is in here

| | |
| --- | --- |
| `watch.rb` | builds, interprets, and writes a frame per wait. The Ruby half |
| `extension.js` | starts that in the project and hands each line to a panel. Decides nothing about the machine |
| `media/panel.html` | the panel: the whole of what is drawn, and the slider |
| `package.json` | one command, one setting |

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
