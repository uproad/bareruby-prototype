# ESP-IDF binding

ESP-IDF is one surface to call over the whole ESP32 family, whose members split across two
instruction sets — Xtensa on the ESP32, S2 and S3, RISC-V on the C3, C6 and H2. That is why
the instruction set is named separately from the binding: one `binding.rb` serves all of
them, and `machine/` carries what each board is called and which of its pins things came
out on.

FreeRTOS owns `main` and calls `app_main`, so this binding supplies that rather than an
entry point of its own, and its `PROGRAM_FILE` is named after the program. The build is a
cmake project the SDK's own `project.cmake` drives, and what the first stage declares
everywhere — *these are the translation units this program reached for* — is what one
`idf_component_register` says here.

`freenove-esp32-s3-wroom` is the board this was proved on: an ESP32-S3-WROOM-1 N16R8
module, two Xtensa LX7 cores at 240 MHz, 16 MB of flash and 8 MB of PSRAM, with its serial
port brought out twice — through a CH343 bridge and through the chip's own USB — and its
indicator brought out as a single addressable RGB device.

## Which of the SDK a build compiles

ESP-IDF ships each driver as a component of its own, and a component nothing requires is
never configured, never compiled and never linked. So the split the first stage already
makes — the units a program touched against the ones it did not — carries straight through
into a build system this side does not own: `build.rb` turns the reached units into the
component list, and a program that never names a pin builds no GPIO driver at all.

## Where a board's own facts live

Every pin this binding needs a number for arrives from `machine/` as a compile definition
rather than as a number written into a unit — the indicator's pin, the two I2C buses, the
pins each serial line comes out on. The units are written in terms of the names, so the
next board through this binding is a file in `machine/` and nothing else.

## What this SDK cannot be asked for

- **The receive queue is the driver's, and it is bought by opening the line.** ESP-IDF will
  not send on a line whose driver is not installed, and installing one allocates its
  receive ring — so a program that only writes pays for a queue it never reads, which on a
  board whose ring this binding owned it would not. `UART.new(..., rx_buffer_size: n)` is
  honoured, except that the driver will not take a queue smaller than the hardware FIFO it
  drains: anything under 129 bytes is raised to that.
- **A peek holds a byte outside the queue.** The driver takes a byte off its ring and
  cannot put it back, so looking at what is next without taking it keeps one byte here.
  `bytes_available` counts it, and `clear_rx_buffer` discards it.
- **A break is the pin, not the line.** This driver only sends a break after a payload it
  is sending, so `break` takes the transmit pin back as an output, holds it low for the
  span asked for, and hands it to the line again. Nothing the program did not write goes
  on the wire, and the span is served exactly.
- **A PWM line takes the next channel and the timer that goes with it.** There are eight
  channels and four timers, so a fifth and sixth line share a timer with an earlier one and
  therefore share its frequency. The programs this was written for drive one or two.
- **The converter is not calibrated.** `read` is twelve bits scaled over the 3.1 V the
  widest attenuation reaches. That attenuation is also the least linear, and the per-chip
  calibration ESP-IDF can apply is not applied here — a reading is right to within a few
  per cent rather than to its last bit.
- **The indicator is one device on a wire.** It takes twenty-four bits of colour at a bit
  period no loop of stores can keep, so it is driven by the transmitter that exists for
  exactly that. `on` is a dim white rather than the full scale, which on one of these is
  painful to look at.
- **Exceptions are a configuration rather than a flag.** `--no-exceptions` and its absence
  reach the build as `CONFIG_COMPILER_CXX_EXCEPTIONS`, which is what decides whether the
  unwinder and its tables are linked.

## What a build reaches for

The SDK is a checkout, pinned by tag and commit in `data/sources.lock.yml`. The compilers
are not pinned there and that is not an omission: ESP-IDF installs its own with
`idf_tools.py`, against a table inside that checkout, so the commit pins the compiler as
exactly as it pins the headers. Three of the dozen tools it offers are asked for — the
Xtensa compiler, cmake and ninja. The debugger and the on-chip debug probe are not: a board
is written over its serial port and read back over the same one.

**Every one of the SDK's submodules is named in the lock, and only three are reached by a
build.** The other twenty are a Bluetooth stack, a Wi-Fi stack, Thread, a test framework
and the radio blobs for five chips that are not this one — but the SDK reads every
component before it chooses the ones a program reached, and a component whose sources are
missing stops that reading rather than being passed over. So what has to be present and
what is compiled are two different lists, and the second is no help in writing the first.

Naming them is still worth doing rather than leaving the SDK to fetch its own: it fetches
whole histories, one at a time, for anything it finds missing, and these are fetched at one
commit each. **1.9 GB against the 8.2 GB the SDK's own answer leaves.**

A desk that keeps its own copies says so with `IDF_PATH` and `IDF_TOOLS_PATH`, which still
win — and then nothing is fetched at all.

## What a board is given

ESP-IDF writes three images — a bootloader, a partition table and the program — each to its
own offset in flash. Everything downstream of a build here is one artifact, so the
toolchain merges the three into the single image those offsets describe, and writing a
board is one file at offset zero. The offsets stay the build's answer; nothing on the
flashing side carries a number of its own.

**Which port, and which reset.** A board of this family can bring its serial port out
twice: through a USB-to-serial bridge, and through the chip's own USB peripheral. The
second needs no auto-reset circuit and no button held, which makes it the one that can
always be written — but the only reset that can be driven over it is its own, and the chip
takes that as another request to be flashed. So a board written there is reset by the RTC
watchdog instead, which is a reset from underneath the peripheral, and it boots what it was
just given. A bridge chip holds the reset pin itself and takes the ordinary reset. The
binding decides by the port's USB vendor, so nothing has to be said.
