# The pico-sdk binding

Reaches RP2040 and RP2350 boards through pico-sdk: the toolchain it builds with, the
second stage it starts, and how a `.uf2` gets onto a board. Raspberry Pi Pico, Pico W,
Pico 2 and Pico 2 W.

A binding is written in the words of what it calls on one side and starts a second stage
on the other, so this gem carries both dependencies — the compiler, for what it must
declare, and the ecosystem, for the build and flash it plugs into.
