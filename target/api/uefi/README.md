# UEFI binding

Reserved. Nothing here is implemented yet.

Firmware services are an API surface like any other: text output, timers and bus
protocols are reached by calling into the boot services table rather than a HAL. The
firmware owns the entry point and calls `efi_main`, so this binding is entered from
outside in the same way the STM32Cube and ESP-IDF ones are.

What a machine record holds here is not settled, because what a program can reach depends
on which protocols the firmware publishes rather than on which pins the board has.
