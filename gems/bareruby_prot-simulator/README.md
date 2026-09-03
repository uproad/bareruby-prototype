# The host simulator

An interpreter for the instructions the compiling desk speaks, and the peripherals that
desk carries behind the calls a program makes into one. It reads an artifact rather than
a compilation — the ELF a build left, and nothing that produced it — which is why it
depends on no other gem here and nothing here depends on it.

The host binding looks for it the way the STM32 one looks for Renode: a desk without it
has a target that builds and does not emulate. What it answers is in [`API.md`](API.md).
