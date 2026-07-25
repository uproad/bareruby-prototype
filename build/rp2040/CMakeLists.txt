cmake_minimum_required(VERSION 3.13)

include($ENV{PICO_SDK_PATH}/external/pico_sdk_import.cmake)

# pico-sdk leaves C++ exceptions off unless asked, so whether the unwinder and
# its tables are linked is a decision the first stage records here.
set(PICO_CXX_ENABLE_EXCEPTIONS 0)

project(bareruby_program C CXX ASM)
set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 20)

pico_sdk_init()

add_executable(bareruby_program
    main.cpp
    ../bareruby_binding_rp2040.cpp
)

target_include_directories(bareruby_program PRIVATE ..)
target_compile_options(bareruby_program PRIVATE $<$<COMPILE_LANGUAGE:CXX>:-fno-rtti -fno-exceptions>)
target_link_libraries(bareruby_program pico_stdlib hardware_gpio hardware_pwm hardware_uart hardware_clocks)

pico_enable_stdio_usb(bareruby_program 0)
pico_enable_stdio_uart(bareruby_program 0)

pico_add_extra_outputs(bareruby_program)
