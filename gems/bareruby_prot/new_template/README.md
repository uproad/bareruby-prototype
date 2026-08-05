# A BareRuby project

BareRuby compiles a subset of Ruby ahead of time into C++, which a toolchain and the
target platform's SDK turn into native firmware. There is no VM and no garbage collector:
every type is resolved while compiling.

This tree was written by `bareruby new` and builds without being edited.

```sh
bin/bareruby build      # compile app/main.rb and build it for this machine
./build/*/bareruby_program
```

The program blinks the onboard LED. On the machine doing the compiling there is no LED,
so each call says on fd2 what it would have done — which is what makes running it here
worth doing.

## Reaching a board

1. Uncomment the board's line in the `Gemfile` and run `bundle install`.
2. `bin/bareruby target add` — it asks which board this is and writes the answer into
   `config/target.yml`. Nothing it asks has to be looked up.
3. `bin/bareruby deploy` — compile, build, and write it onto every board recorded there.

`bin/bareruby build --target=NAME` builds one target without flashing, and
`bin/bareruby target list` prints the names that can be used. `bin/bareruby` on its own
prints the rest.

## What is where

| | |
| --- | --- |
| `app/main.rb` | the program. `build` compiles this when no source is named |
| `config/target.yml` | which compositions this project is built for, and what is attached |
| `Gemfile` | what this is built from, and the list of boards that can be reached |
| `build/` | what the compiler and the toolchains wrote. Rewritten in full every run |
