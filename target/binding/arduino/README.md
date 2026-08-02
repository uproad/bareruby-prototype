# Arduino core binding

Reserved. Nothing here is implemented yet.

The Arduino core is one API surface — `digitalWrite`, `Serial`, `Wire`, `analogRead` —
spread over boards that share no instruction set: AVR, SAMD, nRF52, RP2040 and ESP32.
That is why the instruction set is named separately from the binding: one `binding.rb`
serves all of them, and `machine/` carries what each board is called.

The core owns `main` and calls `setup` and `loop`, so this binding supplies those rather
than an entry point of its own, and its `PROGRAM_FILE` is named after the program.
`arduino-cli` builds it, selected by the FQBN each machine records.

AVR is the first machine here whose natural word is not 32 bits, and whether the arena and
the string runtime fit in its SRAM is a question this binding exists to answer.
