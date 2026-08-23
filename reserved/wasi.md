# WASI binding

Reserved. Nothing here is implemented yet.

A sandbox has no peripheral to reach, so every call here lands on a stub that traces
itself, and there is no `machine/` — nothing is behind the call to describe. **That is
where it parts company with the hosted binding**, which reaches one machine: the desk
itself, whose pins and ports the simulator holds.

It is kept apart from the hosted binding because the instruction set is `wasm32` and the
system interface is WASI rather than the C library, not because the peripherals differ.
A board that executes WebAssembly natively is a different matter entirely: that is an
instruction set with a machine under it, and it would be reached through whichever SDK
that board carries.
