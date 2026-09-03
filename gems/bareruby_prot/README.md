# The ecosystem

Everything a user types, and everything that happens after the first stage has written
its C++. `exe/bareruby` is the one executable this ecosystem ships and the only way into
any of it from a shell: `compile`, `build`, `flash`, `new`, `target`.

It knows nothing about how a program is read or lowered, and nothing about how any
machine is reached. It runs the compiler, and it runs whichever binding the composition
names. What a desk is — which boards are on it — is `config/target.yml`, and this gem is
what reads it.
