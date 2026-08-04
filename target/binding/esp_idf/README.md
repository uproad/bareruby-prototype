# ESP-IDF binding

Reserved. Nothing here is implemented yet.

ESP-IDF is one surface to call over the ESP32 family, whose members split across two
instruction sets — Xtensa on ESP32/S2/S3 and RISC-V on C3/C6/H2 — so the binding is one
file and the instruction set is named per target.

FreeRTOS owns `main` and calls `app_main`, which puts this binding in the same shape as
the STM32Cube one: the program is entered from outside, so `PROGRAM_FILE` is named after
the program rather than after an entry point this side does not own. The build declares
its sources to `idf_component_register` instead of writing a build file, the way
`source-list.txt` already does for the Cube project.

`machine/` carries what each development board is called and how its LED is reached: a
plain GPIO on some, an addressable RGB device on others.
