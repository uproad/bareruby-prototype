cmake_minimum_required(VERSION 3.13)

include($ENV{PICO_SDK_PATH}/external/pico_sdk_import.cmake)

project(bareruby_program C CXX ASM)
set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 20)

pico_sdk_init()

add_executable(bareruby_program
    main.cpp
    ../bareruby_binding_rp2040.cpp
    ../bareruby_runtime_stdio.cpp
)

target_include_directories(bareruby_program PRIVATE ..)
target_compile_options(bareruby_program PRIVATE -fno-rtti)
target_link_libraries(bareruby_program pico_stdlib hardware_gpio)

pico_enable_stdio_usb(bareruby_program 1)
pico_enable_stdio_uart(bareruby_program 0)

# Keep the USB device enumerated so the board can be reset into BOOTSEL from
# the host instead of by replugging it with the button held.
target_compile_definitions(bareruby_program PRIVATE
    PICO_STDIO_USB_ENABLE_RESET_VIA_BAUD_RATE=1
    PICO_STDIO_USB_RESET_MAGIC_BAUD_RATE=1200
    PICO_STDIO_USB_ENABLE_RESET_VIA_VENDOR_INTERFACE=1
)

pico_add_extra_outputs(bareruby_program)
