# frozen_string_literal: true

require_relative "runtime_source"
require_relative "binding_declaration"
require_relative "host_binding_source"
require_relative "onboard_led_source"
require_relative "pico_binding_source"

module BareRubyProt
  module Pass
    class CppSourceGenerator
      # The C++ this compiler ships. Which translation units a build is given follows from
      # two answers alone — the machines it is built for, and whether the program lights the
      # on-board LED — so those two are all this needs to name every file and its contents.
      # What a particular build then links out of that set is the manifest's decision, not
      # this one's.
      class SourceSet
        RUNTIME = {
          "bareruby_runtime.h" => RuntimeSource::HEADER,
          "bareruby_runtime_fixed.cpp" => RuntimeSource::FIXED,
          "bareruby_runtime_arena.cpp" => RuntimeSource::ARENA,
          "bareruby_runtime_string.cpp" => RuntimeSource::STRING,
          "bareruby_runtime_throw.cpp" => RuntimeSource::THROW,
          "bareruby_runtime_stdio.cpp" => RuntimeSource::STDIO,
          "bareruby_binding.h" => BindingDeclaration::HEADER
        }.freeze

        HOST_BINDINGS = {
          "bareruby_binding_host.cpp" => HostBindingSource::PERIPHERAL,
          "bareruby_binding_uart_receive_host.cpp" => HostBindingSource::UART_RECEIVE,
          "bareruby_binding_i2c_host.cpp" => HostBindingSource::I2C,
          "bareruby_binding_i2c_read_host.cpp" => HostBindingSource::I2C_READ
        }.freeze

        # The on-board LED is the one peripheral whose implementation two boards of the
        # same chip disagree about, so it is split by the target's answer rather than by
        # the kind of machine.
        ONBOARD_LED = {
          host: ["bareruby_binding_onboard_led_host.cpp", OnboardLedSource::HOST],
          pin: ["bareruby_binding_onboard_led_pin.cpp", OnboardLedSource::PIN],
          wireless: ["bareruby_binding_onboard_led_wireless.cpp", OnboardLedSource::WIRELESS]
        }.freeze

        # Every Raspberry Pi Pico board shares one binding: the peripherals are reached
        # through pico-sdk, which spells them the same way whichever chip is underneath.
        # Only the board name handed to the SDK tells the two apart.
        PICO_BINDINGS = {
          "bareruby_binding_pico.cpp" => PicoBindingSource::PERIPHERAL,
          "bareruby_binding_uart_receive_pico.cpp" => PicoBindingSource::UART_RECEIVE,
          "bareruby_binding_i2c_pico.cpp" => PicoBindingSource::I2C,
          "bareruby_binding_i2c_read_pico.cpp" => PicoBindingSource::I2C_READ
        }.freeze

        def initialize(targets:, onboard_led:)
          @targets = targets
          @onboard_led = onboard_led
        end

        def files
          sources = RUNTIME.dup
          sources.merge!(HOST_BINDINGS) if @targets.any?(&:hosted?)
          sources.merge!(PICO_BINDINGS) unless @targets.all?(&:hosted?)
          @targets.each { |target| sources.store(*ONBOARD_LED.fetch(target.led)) } if @onboard_led
          sources
        end

        def onboard_led_file_name(target) = ONBOARD_LED.fetch(target.led)[0]
      end
    end
  end
end
