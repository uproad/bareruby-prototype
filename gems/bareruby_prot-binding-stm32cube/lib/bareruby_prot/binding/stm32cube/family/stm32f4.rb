# frozen_string_literal: true

require "erb"

require_relative "stm32f4/clock"

module BareRubyProt
  module Stm32CubeBinding
    # What is true of every STM32F4 and of no other family: where the HAL and CMSIS sit
    # inside the pinned STM32CubeF4 checkout, which HAL translation units a build
    # compiles, how a clock profile becomes code, and how time is measured busily.
    #
    # A family module is the unit a second family adds — F0 arrives as a sibling of this
    # file answering the same questions, with a SysTick delay where this one has the DWT
    # the Cortex-M0 lacks, and its own clock arithmetic. Nothing here is reached except
    # through the answers, so what the questions are is the family boundary.
    module Stm32F4
      KEY = "stm32f4"

      # Paths inside the Cube checkout the lock file names. The checkout's layout is ST's;
      # these say where this family keeps what the build needs of it.
      HAL_SOURCE_DIRECTORY = "Drivers/STM32F4xx_HAL_Driver/Src"
      STARTUP_DIRECTORY = "Drivers/CMSIS/Device/ST/STM32F4xx/Source/Templates/gcc"
      SYSTEM_SOURCE = "Drivers/CMSIS/Device/ST/STM32F4xx/Source/Templates/system_stm32f4xx.c"
      INCLUDE_DIRECTORIES = [
        "Drivers/STM32F4xx_HAL_Driver/Inc",
        "Drivers/CMSIS/Device/ST/STM32F4xx/Include",
        "Drivers/CMSIS/Include"
      ].freeze

      # The HAL translation units every build compiles. The list is short on purpose:
      # what no binding calls is not compiled rather than compiled and dropped, and a
      # missing symbol at link is the signal to lengthen it deliberately.
      HAL_SOURCES = %w[
        stm32f4xx_hal.c
        stm32f4xx_hal_cortex.c
        stm32f4xx_hal_rcc.c
        stm32f4xx_hal_gpio.c
        stm32f4xx_hal_uart.c
        stm32f4xx_hal_i2c.c
        stm32f4xx_hal_tim.c
        stm32f4xx_hal_tim_ex.c
        stm32f4xx_hal_adc.c
        stm32f4xx_hal_adc_ex.c
      ].freeze

      HAL_HEADER = "stm32f4xx_hal.h"
      HAL_CONF_FILE = "stm32f4xx_hal_conf.h"

      def self.clock(board) = Clock.new(board)

      def self.startup(device) = "#{STARTUP_DIRECTORY}/#{device.startup}"

      # ------------------------------------------------------------------------------

      TEMPLATE = File.read(File.expand_path("stm32f4/linker.ld.erb", __dir__))

      def self.linker_script(device, heap: 0x200, stack: 0x400)
        flash = device.flash
        main = device.main_ram
        extras = device.memory - [flash, main]
        width = device.memory.map { |region| region.name.length }.max
        ERB.new(TEMPLATE, trim_mode: "-").result_with_hash(
          device:, flash:, main:, extras:, width:, heap:, stack:
        )
      end

      # ------------------------------------------------------------------------------

      # The HAL asks its user for this file rather than shipping one. Only the modules
      # in HAL_SOURCES are enabled — plus the header-only ones their headers reach for —
      # so reaching an unconfigured peripheral fails at compile rather than at runtime.
      def self.hal_conf(board)
        hse = board.clock["hse_hz"] || 8_000_000
        <<~C
          /* Generated for #{board.key}. The HAL includes this by name. */
          #ifndef STM32F4XX_HAL_CONF_H
          #define STM32F4XX_HAL_CONF_H

          #define HAL_MODULE_ENABLED
          #define HAL_CORTEX_MODULE_ENABLED
          #define HAL_DMA_MODULE_ENABLED    /* header-only: the UART handle carries DMA pointers */
          #define HAL_FLASH_MODULE_ENABLED  /* header-only: RCC sets latency through its macro */
          #define HAL_PWR_MODULE_ENABLED    /* header-only: regulator scaling is a macro */
          #define HAL_EXTI_MODULE_ENABLED
          #define HAL_GPIO_MODULE_ENABLED
          #define HAL_RCC_MODULE_ENABLED
          #define HAL_I2C_MODULE_ENABLED
          #define HAL_UART_MODULE_ENABLED
          #define HAL_TIM_MODULE_ENABLED
          #define HAL_ADC_MODULE_ENABLED

          #define HSE_VALUE #{hse}U
          #define HSE_STARTUP_TIMEOUT 100U
          #define HSI_VALUE #{board.device.clock['hsi_hz']}U
          #define LSI_VALUE 32000U
          #define LSE_VALUE 32768U
          #define LSE_STARTUP_TIMEOUT 5000U
          #define EXTERNAL_CLOCK_VALUE 12288000U

          #define VDD_VALUE 3300U
          #define TICK_INT_PRIORITY 0x0FU
          #define USE_RTOS 0U
          #define PREFETCH_ENABLE 1U
          #define INSTRUCTION_CACHE_ENABLE 1U
          #define DATA_CACHE_ENABLE 1U

          #ifdef HAL_RCC_MODULE_ENABLED
          #include "stm32f4xx_hal_rcc.h"
          #endif
          #ifdef HAL_EXTI_MODULE_ENABLED
          #include "stm32f4xx_hal_exti.h"
          #endif
          #ifdef HAL_GPIO_MODULE_ENABLED
          #include "stm32f4xx_hal_gpio.h"
          #endif
          #ifdef HAL_DMA_MODULE_ENABLED
          #include "stm32f4xx_hal_dma.h"
          #endif
          #ifdef HAL_CORTEX_MODULE_ENABLED
          #include "stm32f4xx_hal_cortex.h"
          #endif
          #ifdef HAL_FLASH_MODULE_ENABLED
          #include "stm32f4xx_hal_flash.h"
          #endif
          #ifdef HAL_PWR_MODULE_ENABLED
          #include "stm32f4xx_hal_pwr.h"
          #endif
          #ifdef HAL_I2C_MODULE_ENABLED
          #include "stm32f4xx_hal_i2c.h"
          #endif
          #ifdef HAL_UART_MODULE_ENABLED
          #include "stm32f4xx_hal_uart.h"
          #endif
          #ifdef HAL_TIM_MODULE_ENABLED
          #include "stm32f4xx_hal_tim.h"
          #include "stm32f4xx_hal_tim_ex.h"
          #endif
          #ifdef HAL_ADC_MODULE_ENABLED
          #include "stm32f4xx_hal_adc.h"
          #endif

          #define assert_param(expr) ((void)0U)

          #endif
        C
      end

      # ------------------------------------------------------------------------------

      # Busy microseconds from the DWT cycle counter, which every Cortex-M4 carries and
      # no Cortex-M0 does — the reason the delay is a family answer and not a common one.
      def self.delay_text
        <<~C
          void bareruby_board_delay_us(uint32_t microseconds) {
              CoreDebug->DEMCR |= CoreDebug_DEMCR_TRCENA_Msk;
              DWT->CTRL |= DWT_CTRL_CYCCNTENA_Msk;
              uint32_t cycles_per_microsecond = SystemCoreClock / 1000000u;
              while (microseconds > 0) {
                  uint32_t batch = microseconds > 1000000u ? 1000000u : microseconds;
                  uint32_t cycles = batch * cycles_per_microsecond;
                  uint32_t start = DWT->CYCCNT;
                  while ((uint32_t)(DWT->CYCCNT - start) < cycles) {
                  }
                  microseconds -= batch;
              }
          }
        C
      end

      # ------------------------------------------------------------------------------

      # The machine for Renode, written from the same manifests the firmware was. The
      # base platform is Renode's own STM32F4; what the manifests correct is what the
      # firmware actually touches: the DWT counter every delay above busy-waits on —
      # absent from the base, and a counter that never moves is that loop never ending —
      # this device's memory sizes, and the board's LED.
      def self.renode_platform(board, clock)
        text = <<~REPL
          using "platforms/cpus/stm32f4.repl"

          // The delays busy-wait on DWT->CYCCNT, so the counter advances at the proved
          // SYSCLK — a millisecond asked for is a virtual millisecond. SysTick is what
          // HAL timeouts are measured against, so it runs at the same clock.
          dwt: Miscellaneous.DWT @ sysbus 0xE0001000
              frequency: #{clock.sysclk}

          nvic:
              systickFrequency: #{clock.sysclk}

          flash:
              size: #{format('0x%X', board.device.flash.size)}

          sram:
              size: #{format('0x%X', board.device.main_ram.size)}
        REPL
        return text unless board.led

        pin = board.led.pin
        <<~REPL
          #{text.chomp}

          led: Miscellaneous.LED @ gpioPort#{pin.port} #{pin.index}
              invert: #{board.led.active_high? ? 'false' : 'true'}

          gpioPort#{pin.port}:
              #{pin.index} -> led@0
        REPL
      end

      # Where the family's UARTs sit on the bus — the reference manual's memory map,
      # which no board changes.
      UART_BASES = {
        "USART1" => 0x40011000, "USART2" => 0x40004400, "USART3" => 0x40004800,
        "UART4" => 0x40004C00, "UART5" => 0x40005000, "USART6" => 0x40011400
      }.freeze

      # CR1 with UE and RE set: the receiver listening and nothing else decided.
      # Emulation writes it before the first instruction, because Renode's model drops
      # what arrives while the receiver is off — the firmware's own init then configures
      # the port over this without touching what already queued.
      def self.uart_receiver_on(instance) = [UART_BASES.fetch(instance) + 0x0C, 0x2004]
    end

    # The families this gem carries, by the key a device manifest names. F0 and F7 are
    # additions to this table and siblings of the module above — nothing outside it
    # learns a family any other way.
    FAMILIES = { Stm32F4::KEY => Stm32F4 }.freeze
  end
end
