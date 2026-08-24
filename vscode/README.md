# Watching a program run

The second half of the simulator: what the first half knows, shown to somebody.

The machine the host build runs on carries peripherals — pins that hold a level, ports
that keep what they sent, a clock that moves — and after a run they are all still there
to be read. This turns that into a panel: the pins as lamps, the serial ports as their
buffers, the square waves as their duty, and a slider along the run so any moment in it
can be looked at.

**A blink looks like a blink here.** The clock is virtual, so a three-second run finishes
in a fraction of a second and every frame of it arrives at once; the slider is what makes
that watchable rather than a single final state.

## Running it

Two halves, and the Ruby one is useful on its own.

```sh
ruby vscode/watch.rb samples/blink.rb 3
{"ms":500,"gpio":{"25":{"pin":25,"level":1,"changes":1,...}},...}
{"ms":1000,"gpio":{"25":{"pin":25,"level":0,"changes":2,...}},...}
```

It builds the program for the hosted entry, interprets what the build left, and writes
**one line of JSON every time the program waits** — which is every time the machine can
have changed. The last line is the run's end, marked `"over":true`. Nothing about those
lines is specific to an editor.

A program that receives takes its bytes from a file named third, the same files the checks
are fed from:

```sh
ruby vscode/watch.rb samples/uart_receive.rb 3 checks/input/uart_receive.txt
```

The extension reads them into a panel:

```sh
code --extensionDevelopmentPath=$PWD/vscode $PWD
```

or open this repository in VS Code, press <kbd>F5</kbd>, and in the window that opens run
**BareRuby: Watch this program run** from the command palette. It watches the `.rb` file
in front of you, or `samples/blink.rb` when that is not one. How much virtual time a run
gets is `bareruby.seconds` in settings, 3 by default.

## What is in here

| | |
| --- | --- |
| `watch.rb` | builds, interprets, and writes a frame per wait. The Ruby half |
| `extension.js` | starts that and hands each line to a panel. Decides nothing about the machine |
| `media/panel.html` | the panel: the whole of what is drawn, and the slider |
| `package.json` | one command, one setting |

**There is no build step.** It is plain JavaScript, loaded as it is — a throwaway has no
business growing an npm toolchain, and nothing here is large enough to want one.

## What it does not do

- **It only watches.** The first half can move a pin (`machine.change`), answer an ADC and
  put bytes on a wire while a program runs, and none of that is wired to the panel yet.
  Doing it would make the channel a conversation rather than a stream, which is a step of
  its own.
- **It shows one run.** Starting the command again opens another panel; there is nothing
  that compares two.
- **The command feeds nothing.** `watch.rb` takes an input file, the panel's command does
  not name one — so a program that waits on its serial port shows an empty queue when it
  is started from the palette.
- **Bytes are shown printable.** What a port sent is rendered with `\xNN` for anything
  that is not a printable character, which is what makes it a string a panel can hold.
