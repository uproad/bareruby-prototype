# frozen_string_literal: true

require "fileutils"

require_relative "manifests"

module BareRubyProt
  module Stm32CubeBinding
    # `bareruby init stm32`. Writes the project layer's shape into the project, as
    # templates: the directories a build already searches, holding one sample board and
    # one sample device with every field explained in place.
    #
    # **A template is not yet a manifest.** The files land as `.yml.sample`, which the
    # build's `*.yml` glob does not see — nothing becomes a target because this command
    # ran. Renaming a file is the act of meaning it, and from that moment it is proved
    # like any other manifest.
    #
    # Idempotent the way install.sh is: what exists is left alone and said to be left
    # alone, so running it again after a template change writes only what is missing.
    module Stm32CubeInit
      BOARD_TEMPLATE = <<~YAML
        # A board of this project's own. Rename this file to <key>.yml to make it a
        # target — the .sample suffix keeps it invisible to the build until then.
        #
        # Reusing a key the gem already carries (say, nucleo_f446re) replaces the gem's
        # record for this project: the way to move a pin or correct official data
        # without editing the gem. Files replace whole — copy the gem's file and change
        # what differs. The build manifest records board_source = project:<this file>
        # whenever the project's record answered.
        key: my_board
        name: stm32-my-board   # the composition's name, as `bareruby target list` prints
                               # it and as an entry in config/target.yml is offered it
        family: stm32f4
        device: stm32f401retx  # any device either layer defines
        # Proved against the device's limits before any C is generated; a profile that
        # violates them is refused with the figure and the bound in the message.
        clock:
          source: hsi          # hsi, or hse-crystal with hse_hz: beside it
          pll: { m: 16, n: 336, p: 4, q: 7 }
          ahb_divider: 1
          apb1_divider: 2
          apb2_divider: 1
          regulator_scale: 2
        led:                   # leave the whole key out if the board has no LED —
          pin: PB0             # OnboardLED then refuses at compile time, naming this file
          active_high: true
        uart:
          # id is what a program says: UART.new(0). stdout: true routes puts here.
          - id: 0
            instance: USART2
            tx: { pin: PA2, af: 7 }
            rx: { pin: PA3, af: 7 }
            stdout: true
        i2c:
          - id: 0
            instance: I2C1
            scl: { pin: PB8, af: 4 }
            sda: { pin: PB9, af: 4 }
        probe:
          openocd: { interface: stlink, target: stm32f4x }
      YAML

      DEVICE_TEMPLATE = <<~YAML
        # An MCU the gem does not carry, described from its datasheet. Rename this file
        # to <key>.yml to make it real — the .sample suffix keeps it invisible to the
        # build until then.
        #
        # Start from the gem's nearest data/<family>/devices/*.yml and change what the
        # datasheet says; these figures are the STM32F401RETx's.
        key: my_device         # how boards name this chip: device: my_device
        family: stm32f4
        part: STM32F401RET6    # the order code, recorded in the build manifest
        define: STM32F401xE    # the CMSIS device define the HAL compiles under
        core: cortex-m4
        fpu: fpv4-sp-d16       # or none — none also means float_abi: soft
        float_abi: hard
        startup: startup_stm32f401xe.s   # from the Cube checkout's Templates/gcc
        memory:
          # Every region, tagged by role. code and main are required; extra RAMs
          # (role: ccm, fast) become named NOLOAD sections in the linker script.
          - name: FLASH
            kind: flash
            origin: 0x08000000
            size: 512K
            role: code
          - name: RAM
            kind: ram
            origin: 0x20000000
            size: 96K
            role: main
        gpio_ports: [A, B, C, D, H]      # ports the package bonds out
        uarts: [USART1, USART2, USART6]  # instances a board may wire
        i2cs: [I2C1, I2C2, I2C3]
        clock:
          hsi_hz: 16000000
          max_sysclk_hz: 84000000
          max_apb1_hz: 42000000
          max_apb2_hz: 84000000
          vco_in_hz: [1000000, 2000000]
          vco_out_hz: [192000000, 432000000]
          flash_wait_hz: 30000000        # Hz of HCLK per flash wait state
      YAML

      TEMPLATES = {
        File.join("boards", "my_board.yml.sample") => BOARD_TEMPLATE,
        File.join("devices", "my_device.yml.sample") => DEVICE_TEMPLATE
      }.freeze

      def self.run
        TEMPLATES.each { |name, content| write(name, content) }
        said
        0
      end

      # The same constant the build reads from, so init and build cannot disagree about
      # where the project layer is.
      def self.place(name) = File.join(Manifests::PROJECT_DATA, name)

      def self.write(name, content)
        path = place(name)
        return puts "  kept   #{name} (already there)" if File.exist?(path)

        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, content)
        puts "  wrote  #{name}"
      end

      def self.said
        puts <<~SAID

          Templates are in #{Manifests::PROJECT_DATA}.
          Rename a .yml.sample to <key>.yml and it is a target: build it with
          --target=<name>. On one key, your file wins over the gem's.

          If the toolchain is not installed yet, see this gem's setup.md — one
          install.sh run per desk.
        SAID
      end
    end
  end
end
