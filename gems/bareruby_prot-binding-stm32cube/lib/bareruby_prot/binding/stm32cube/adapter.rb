# frozen_string_literal: true

require_relative "manifests"
require_relative "family/stm32f4"

module BareRubyProt
  module Stm32CubeBinding
    # The generated pair bareruby_board.h/.c — the stable boundary between the common
    # binding and one particular board. The adapter owns every HAL handle, every pin,
    # every alternate function and the clock; the binding above it speaks logical ids
    # and nothing else, which is what lets one binding serve every board and every
    # family without naming any.
    #
    # Peripherals initialize on first reach: a program that never says UART carries a
    # handle table entry and no configured USART. What a board does not have is not in
    # the header at all — a program reaching for the LED of a board without one fails
    # before this file is even generated, at unit selection.
    class Adapter
      def initialize(board)
        @board = board
        @device = board.device
        @family = FAMILIES.fetch(board.family)
      end

      def files = { "bareruby_board.h" => header, "bareruby_board.c" => source }

      # ------------------------------------------------------------------------------

      def header
        <<~C
          /* Generated for #{@board.key} (#{@device.part}). The one boundary the common
           * binding sees; everything behind it belongs to this board. */
          #ifndef BARERUBY_BOARD_H
          #define BARERUBY_BOARD_H

          #include <stdbool.h>
          #include <stdint.h>

          #include "#{@family::HAL_HEADER}"

          #ifdef __cplusplus
          extern "C" {
          #endif

          /* HAL, the clock profile, and nothing else — peripherals wait to be reached. */
          void bareruby_board_start(void);

          /* Where refusal lands: interrupts off, and a loop a debugger finds. */
          void bareruby_board_fault(void);

          /* NULL for a port this package does not bond out. */
          GPIO_TypeDef *bareruby_board_gpio_port(int32_t index);
          void bareruby_board_gpio_clock(int32_t index);

          /* Wired, clocked and initialized on first reach; a fault for an id this
           * board does not offer. */
          UART_HandleTypeDef *bareruby_board_uart(int32_t id);
          I2C_HandleTypeDef *bareruby_board_i2c(int32_t id);

          void bareruby_board_delay_us(uint32_t microseconds);
          #{stdout_define}#{led_declarations}
          #ifdef __cplusplus
          }
          #endif

          #endif
        C
      end

      def stdout_define
        stdout = @board.stdout_uart
        return "" unless stdout

        "\n/* The UART wired to where a desk can watch: this board's stdout. */\n" \
          "#define BARERUBY_BOARD_STDOUT_UART #{stdout.id}\n"
      end

      def led_declarations
        return "" unless @board.led

        "\nvoid bareruby_board_led_initialize(void);\nvoid bareruby_board_led_write(bool value);\n"
      end

      # ------------------------------------------------------------------------------

      def source
        sections = [source_head, fault_text, clock_text, start_text, gpio_text]
        sections << uart_text unless @board.uarts.empty?
        sections << i2c_text unless @board.i2cs.empty?
        sections << led_text if @board.led
        sections << @family.delay_text
        sections.join("\n")
      end

      def source_head
        <<~C
          /* Generated for #{@board.key}. */
          #include "bareruby_board.h"

        C
      end

      def fault_text
        <<~C
          void bareruby_board_fault(void) {
              __disable_irq();
              for (;;) {
              }
          }

          /* HAL_Delay counts on this arriving every millisecond. The startup file's
           * default handler is an infinite loop, so the definition is not optional. */
          void SysTick_Handler(void) {
              HAL_IncTick();
          }

        C
      end

      def clock_text = @family.clock(@board).configure_text

      def start_text
        <<~C

          void bareruby_board_start(void) {
              if (HAL_Init() != HAL_OK) {
                  bareruby_board_fault();
              }
              bareruby_board_clock();
          }

        C
      end

      # Only the ports the package bonds out have cases; the rest answer NULL and let
      # the binding refuse. Index 0 is port A everywhere.
      def gpio_text
        ports = @device.gpio_ports
        port_cases = ports.map do |port|
          "    case #{index_of(port)}: return GPIO#{port};"
        end
        clock_cases = ports.map do |port|
          "    case #{index_of(port)}: __HAL_RCC_GPIO#{port}_CLK_ENABLE(); break;"
        end
        <<~C
          GPIO_TypeDef *bareruby_board_gpio_port(int32_t index) {
              switch (index) {
          #{port_cases.join("\n")}
              default: return NULL;
              }
          }

          void bareruby_board_gpio_clock(int32_t index) {
              switch (index) {
          #{clock_cases.join("\n")}
              default: bareruby_board_fault();
              }
          }

        C
      end

      def index_of(port) = port.ord - "A".ord

      # ------------------------------------------------------------------------------

      def uart_text
        handles = @board.uarts.map { |channel| uart_handle(channel) }
        cases = @board.uarts.map do |channel|
          "    case #{channel.id}: return bareruby_board_uart_#{channel.id}();"
        end
        <<~C
          #{handles.join("\n")}
          UART_HandleTypeDef *bareruby_board_uart(int32_t id) {
              switch (id) {
          #{cases.join("\n")}
              default: bareruby_board_fault(); return NULL;
              }
          }

        C
      end

      def uart_handle(channel)
        <<~C
          static UART_HandleTypeDef bareruby_board_uart_#{channel.id}_handle;

          static UART_HandleTypeDef *bareruby_board_uart_#{channel.id}(void) {
              UART_HandleTypeDef *port = &bareruby_board_uart_#{channel.id}_handle;
              if (port->Instance == NULL) {
                  __HAL_RCC_#{channel.instance}_CLK_ENABLE();
          #{wire_text(channel, 'GPIO_MODE_AF_PP', 'GPIO_NOPULL')}
                  port->Instance = #{channel.instance};
                  port->Init.BaudRate = 115200;
                  port->Init.WordLength = UART_WORDLENGTH_8B;
                  port->Init.StopBits = UART_STOPBITS_1;
                  port->Init.Parity = UART_PARITY_NONE;
                  port->Init.Mode = UART_MODE_TX_RX;
                  port->Init.HwFlowCtl = UART_HWCONTROL_NONE;
                  port->Init.OverSampling = UART_OVERSAMPLING_16;
                  if (HAL_UART_Init(port) != HAL_OK) {
                      bareruby_board_fault();
                  }
              }
              return port;
          }
        C
      end

      def i2c_text
        handles = @board.i2cs.map { |channel| i2c_handle(channel) }
        cases = @board.i2cs.map do |channel|
          "    case #{channel.id}: return bareruby_board_i2c_#{channel.id}();"
        end
        <<~C
          #{handles.join("\n")}
          I2C_HandleTypeDef *bareruby_board_i2c(int32_t id) {
              switch (id) {
          #{cases.join("\n")}
              default: bareruby_board_fault(); return NULL;
              }
          }

        C
      end

      def i2c_handle(channel)
        <<~C
          static I2C_HandleTypeDef bareruby_board_i2c_#{channel.id}_handle;

          static I2C_HandleTypeDef *bareruby_board_i2c_#{channel.id}(void) {
              I2C_HandleTypeDef *bus = &bareruby_board_i2c_#{channel.id}_handle;
              if (bus->Instance == NULL) {
                  __HAL_RCC_#{channel.instance}_CLK_ENABLE();
          #{wire_text(channel, 'GPIO_MODE_AF_OD', 'GPIO_NOPULL')}
                  bus->Instance = #{channel.instance};
                  bus->Init.ClockSpeed = 100000;
                  bus->Init.DutyCycle = I2C_DUTYCYCLE_2;
                  bus->Init.OwnAddress1 = 0;
                  bus->Init.AddressingMode = I2C_ADDRESSINGMODE_7BIT;
                  bus->Init.DualAddressMode = I2C_DUALADDRESS_DISABLE;
                  bus->Init.OwnAddress2 = 0;
                  bus->Init.GeneralCallMode = I2C_GENERALCALL_DISABLE;
                  bus->Init.NoStretchMode = I2C_NOSTRETCH_DISABLE;
                  if (HAL_I2C_Init(bus) != HAL_OK) {
                      bareruby_board_fault();
                  }
              }
              return bus;
          }
        C
      end

      # One HAL_GPIO_Init per wire: uniform whether or not the two ends share a port,
      # and the alternate function stays the manifest's number rather than a macro
      # whose name would have to be derived.
      def wire_text(channel, mode, pull)
        channel.wires.map do |name, wire|
          <<~C.chomp
                  {
                      /* #{name}: #{wire.pin.name}, AF#{wire.af} */
                      __HAL_RCC_GPIO#{wire.pin.port}_CLK_ENABLE();
                      GPIO_InitTypeDef wires = {0};
                      wires.Pin = GPIO_PIN_#{wire.pin.index};
                      wires.Mode = #{mode};
                      wires.Pull = #{pull};
                      wires.Speed = GPIO_SPEED_FREQ_VERY_HIGH;
                      wires.Alternate = #{wire.af}U;
                      HAL_GPIO_Init(GPIO#{wire.pin.port}, &wires);
                  }
          C
        end.join("\n")
      end

      def led_text
        led = @board.led
        port = "GPIO#{led.pin.port}"
        pin = "GPIO_PIN_#{led.pin.index}"
        on = led.active_high? ? "GPIO_PIN_SET" : "GPIO_PIN_RESET"
        off = led.active_high? ? "GPIO_PIN_RESET" : "GPIO_PIN_SET"
        <<~C
          void bareruby_board_led_initialize(void) {
              __HAL_RCC_GPIO#{led.pin.port}_CLK_ENABLE();
              GPIO_InitTypeDef wire = {0};
              wire.Pin = #{pin};
              wire.Mode = GPIO_MODE_OUTPUT_PP;
              wire.Pull = GPIO_NOPULL;
              wire.Speed = GPIO_SPEED_FREQ_LOW;
              HAL_GPIO_Init(#{port}, &wire);
              HAL_GPIO_WritePin(#{port}, #{pin}, #{off});
          }

          void bareruby_board_led_write(bool value) {
              HAL_GPIO_WritePin(#{port}, #{pin}, value ? #{on} : #{off});
          }

        C
      end
    end
  end
end
