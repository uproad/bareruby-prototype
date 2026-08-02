# Machines reached through pico-sdk

Reserved. The board names this binding hands to the SDK are still carried on the machine
records themselves, because every board here is reached through exactly one API and
nothing yet forces the two apart.

They move here when a board becomes reachable through a second API — arduino-pico
reaches these same boards — because at that point `pico_w` is what pico-sdk calls the
board, not what the board is.
