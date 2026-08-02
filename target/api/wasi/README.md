# WASI binding

Reserved. Nothing here is implemented yet.

A sandbox has no peripheral to reach, so this binding answers the same way the hosted one
does: every call lands on a stub that traces itself. It has no `machine/` for the same
reason — there is no board.

It is kept apart from the hosted binding because the instruction set is `wasm32` and the
system interface is WASI rather than the C library, not because the peripherals differ.
A board that executes WebAssembly natively is a different matter entirely: that is an
instruction set with a machine under it, and it would be reached through whichever SDK
that board carries.
