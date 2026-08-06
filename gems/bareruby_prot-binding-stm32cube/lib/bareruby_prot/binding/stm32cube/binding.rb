# frozen_string_literal: true

require_relative "manifests"
require_relative "build"
require_relative "toolchain"
require_relative "flash"
require_relative "init"

module BareRubyProt
  module Stm32CubeBinding
    # The C this binding contributes. None of it names a board or a family: every
    # handle, pin and clock is reached through the generated board adapter, which is
    # what lets these translation units serve an F401 and an F446 today and an F0
    # tomorrow without a line changing. A peripheral that can be uninstalled still
    # cannot share a file with one that cannot.
    UART = <<~CPP
      #include "bareruby_binding.h"
      #include <stdarg.h>
      #include <stdio.h>
      #include <string.h>
      #include "bareruby_board.h"

      void bareruby_uart_init(bareruby_uart_t *self, int32_t id, int32_t baud, int32_t parity) {
          self->id = id;
          self->baud = baud;
          self->parity = parity;
          UART_HandleTypeDef *port = bareruby_board_uart(id);
          uint32_t hal_parity = UART_PARITY_NONE;
          if (parity == 1) {
              hal_parity = UART_PARITY_EVEN;
          } else if (parity == 2) {
              hal_parity = UART_PARITY_ODD;
          } else if (parity != 0) {
              bareruby_board_fault();
          }

          uint32_t word_length = hal_parity == UART_PARITY_NONE ? UART_WORDLENGTH_8B : UART_WORDLENGTH_9B;
          if (port->Init.BaudRate != (uint32_t)baud || port->Init.Parity != hal_parity ||
              port->Init.WordLength != word_length) {
              if (HAL_UART_DeInit(port) != HAL_OK) {
                  bareruby_board_fault();
              }
              port->Init.BaudRate = (uint32_t)baud;
              port->Init.WordLength = word_length;
              port->Init.StopBits = UART_STOPBITS_1;
              port->Init.Parity = hal_parity;
              port->Init.Mode = UART_MODE_TX_RX;
              port->Init.HwFlowCtl = UART_HWCONTROL_NONE;
              port->Init.OverSampling = UART_OVERSAMPLING_16;
              if (HAL_UART_Init(port) != HAL_OK) {
                  bareruby_board_fault();
              }
          }
      }

      int32_t bareruby_uart_write(bareruby_uart_t *self, const char *value) {
          int32_t length = (int32_t)strlen(value);
          HAL_StatusTypeDef status = HAL_UART_Transmit(
              bareruby_board_uart(self->id), (uint8_t *)value, (uint16_t)length, HAL_MAX_DELAY);
          return status == HAL_OK ? length : -1;
      }

      void bareruby_uart_puts(bareruby_uart_t *self, const char *value) {
          (void)bareruby_uart_write(self, value);
          static uint8_t newline = '\\n';
          (void)HAL_UART_Transmit(bareruby_board_uart(self->id), &newline, 1, HAL_MAX_DELAY);
      }

      void bareruby_uart_printf(bareruby_uart_t *self, const char *format, ...) {
          char payload[256];
          va_list arguments;
          va_start(arguments, format);
          int length = vsnprintf(payload, sizeof(payload), format, arguments);
          va_end(arguments);
          if (length <= 0) {
              return;
          }
          uint16_t transmitted = (uint16_t)(length < (int)sizeof(payload) ? length : (int)sizeof(payload) - 1);
          (void)HAL_UART_Transmit(
              bareruby_board_uart(self->id), (uint8_t *)payload, transmitted, HAL_MAX_DELAY);
      }

      int32_t bareruby_uart_bytes_available(bareruby_uart_t *self) {
          return __HAL_UART_GET_FLAG(bareruby_board_uart(self->id), UART_FLAG_RXNE) != RESET ? 1 : 0;
      }

      bool bareruby_uart_can_read_line(bareruby_uart_t *self) {
          return bareruby_uart_bytes_available(self) != 0;
      }

      void bareruby_uart_flush(bareruby_uart_t *self) {
          UART_HandleTypeDef *port = bareruby_board_uart(self->id);
          while (__HAL_UART_GET_FLAG(port, UART_FLAG_TC) == RESET) {
          }
      }

      void bareruby_uart_clear_rx_buffer(bareruby_uart_t *self) {
          UART_HandleTypeDef *port = bareruby_board_uart(self->id);
          while (__HAL_UART_GET_FLAG(port, UART_FLAG_RXNE) != RESET) {
              __HAL_UART_FLUSH_DRREGISTER(port);
          }
      }

      void bareruby_uart_clear_tx_buffer(bareruby_uart_t *self) {
          bareruby_uart_flush(self);
      }
    CPP

    GPIO = <<~CPP
      #include "bareruby_binding.h"
      #include "bareruby_board.h"

      /* The public GPIO API currently carries one realtime handler, just like the Pico
         and Arduino bindings. STM32 gives each pin number one EXTI line, with lines 5--9
         and 10--15 sharing vectors; the seven strong handlers below replace the startup
         file's weak defaults and hand those vectors to HAL. */
      static bareruby_interrupt_handler_t bareruby_gpio_interrupt_handler;
      static uint16_t bareruby_gpio_interrupt_pin;

      static IRQn_Type bareruby_gpio_interrupt_irq(int32_t pin) {
          switch ((uint32_t)pin & 15u) {
          case 0: return EXTI0_IRQn;
          case 1: return EXTI1_IRQn;
          case 2: return EXTI2_IRQn;
          case 3: return EXTI3_IRQn;
          case 4: return EXTI4_IRQn;
          case 5:
          case 6:
          case 7:
          case 8:
          case 9: return EXTI9_5_IRQn;
          default: return EXTI15_10_IRQn;
          }
      }

      extern "C" void HAL_GPIO_EXTI_Callback(uint16_t pin) {
          if (pin == bareruby_gpio_interrupt_pin && bareruby_gpio_interrupt_handler != NULL) {
              bareruby_gpio_interrupt_handler();
          }
      }

      extern "C" void EXTI0_IRQHandler(void) {
          HAL_GPIO_EXTI_IRQHandler(GPIO_PIN_0);
      }

      extern "C" void EXTI1_IRQHandler(void) {
          HAL_GPIO_EXTI_IRQHandler(GPIO_PIN_1);
      }

      extern "C" void EXTI2_IRQHandler(void) {
          HAL_GPIO_EXTI_IRQHandler(GPIO_PIN_2);
      }

      extern "C" void EXTI3_IRQHandler(void) {
          HAL_GPIO_EXTI_IRQHandler(GPIO_PIN_3);
      }

      extern "C" void EXTI4_IRQHandler(void) {
          HAL_GPIO_EXTI_IRQHandler(GPIO_PIN_4);
      }

      extern "C" void EXTI9_5_IRQHandler(void) {
          HAL_GPIO_EXTI_IRQHandler(GPIO_PIN_5);
          HAL_GPIO_EXTI_IRQHandler(GPIO_PIN_6);
          HAL_GPIO_EXTI_IRQHandler(GPIO_PIN_7);
          HAL_GPIO_EXTI_IRQHandler(GPIO_PIN_8);
          HAL_GPIO_EXTI_IRQHandler(GPIO_PIN_9);
      }

      extern "C" void EXTI15_10_IRQHandler(void) {
          HAL_GPIO_EXTI_IRQHandler(GPIO_PIN_10);
          HAL_GPIO_EXTI_IRQHandler(GPIO_PIN_11);
          HAL_GPIO_EXTI_IRQHandler(GPIO_PIN_12);
          HAL_GPIO_EXTI_IRQHandler(GPIO_PIN_13);
          HAL_GPIO_EXTI_IRQHandler(GPIO_PIN_14);
          HAL_GPIO_EXTI_IRQHandler(GPIO_PIN_15);
      }

      /* Pin numbering is sixteen to a port, port A first — the family's own order.
         Which ports exist is the adapter's answer, so a pin on a port this package
         does not bond out is refused rather than aliased. */
      static GPIO_TypeDef *bareruby_gpio_port(int32_t pin) {
          GPIO_TypeDef *port = bareruby_board_gpio_port(pin / 16);
          if (port == NULL) {
              bareruby_board_fault();
          }
          return port;
      }

      static uint16_t bareruby_gpio_pin(int32_t pin) {
          if (pin < 0 || pin >= 176) {
              bareruby_board_fault();
          }
          return (uint16_t)(1u << ((uint32_t)pin & 15u));
      }

      void bareruby_gpio_init(bareruby_gpio_t *self, int32_t pin, int32_t params) {
          self->pin = pin;
          self->params = params;
          GPIO_TypeDef *port = bareruby_gpio_port(pin);
          bareruby_board_gpio_clock(pin / 16);

          GPIO_InitTypeDef config = {};
          config.Pin = bareruby_gpio_pin(pin);
          config.Pull = (params & 8) ? GPIO_PULLUP : ((params & 16) ? GPIO_PULLDOWN : GPIO_NOPULL);
          config.Speed = GPIO_SPEED_FREQ_LOW;
          if (params & 2) {
              config.Mode = (params & 32) ? GPIO_MODE_OUTPUT_OD : GPIO_MODE_OUTPUT_PP;
          } else {
              config.Mode = GPIO_MODE_INPUT;
          }
          HAL_GPIO_Init(port, &config);
      }

      void bareruby_gpio_write(bareruby_gpio_t *self, int32_t value) {
          HAL_GPIO_WritePin(
              bareruby_gpio_port(self->pin), bareruby_gpio_pin(self->pin),
              value != 0 ? GPIO_PIN_SET : GPIO_PIN_RESET);
      }

      int32_t bareruby_gpio_read(bareruby_gpio_t *self) {
          return HAL_GPIO_ReadPin(bareruby_gpio_port(self->pin), bareruby_gpio_pin(self->pin)) ==
                         GPIO_PIN_SET
                     ? 1
                     : 0;
      }

      bool bareruby_gpio_high(bareruby_gpio_t *self) {
          return bareruby_gpio_read(self) != 0;
      }

      bool bareruby_gpio_low(bareruby_gpio_t *self) {
          return bareruby_gpio_read(self) == 0;
      }

      void bareruby_gpio_on_interrupt(
          bareruby_gpio_t *self, int32_t events, bareruby_interrupt_handler_t handler) {
          GPIO_TypeDef *port = bareruby_gpio_port(self->pin);
          uint16_t pin = bareruby_gpio_pin(self->pin);
          IRQn_Type interrupt = bareruby_gpio_interrupt_irq(self->pin);

          GPIO_InitTypeDef config = {};
          config.Pin = pin;
          config.Mode = (events & 4) ? GPIO_MODE_IT_FALLING : GPIO_MODE_IT_RISING;
          config.Pull = (self->params & 8) ? GPIO_PULLUP
                                           : ((self->params & 16) ? GPIO_PULLDOWN : GPIO_NOPULL);

          bareruby_gpio_interrupt_handler = handler;
          bareruby_gpio_interrupt_pin = pin;
          HAL_GPIO_Init(port, &config);

          /* Do not deliver an edge left pending while the pin and callback were being
             installed. Priority 2 is the value ST's own F446 GPIO EXTI example uses. */
          __HAL_GPIO_EXTI_CLEAR_IT(pin);
          HAL_NVIC_ClearPendingIRQ(interrupt);
          HAL_NVIC_SetPriority(interrupt, 2, 0);
          HAL_NVIC_EnableIRQ(interrupt);
      }
    CPP

    PERIPHERAL = <<~CPP
      #include "bareruby_binding.h"

      #include <stdio.h>

      #include "bareruby_board.h"

      /* newlib's printf leaves by _write. It leaves for the board's stdout UART when
         the board has one; a board without one has no _write, and the first stage has
         already dropped the calls that would have needed it. */
      #ifdef BARERUBY_BOARD_STDOUT_UART
      extern "C" int _write(int file, char *data, int length) {
          (void)file;
          if (HAL_UART_Transmit(bareruby_board_uart(BARERUBY_BOARD_STDOUT_UART),
                                (uint8_t *)data, (uint16_t)length, HAL_MAX_DELAY) != HAL_OK) {
              return -1;
          }
          return length;
      }
      #endif

      void bareruby_startup(void) {
          /* The board adapter has already brought HAL and the clock up in main. */
      }

      void bareruby_machine_delay_us(int32_t microseconds) {
          if (microseconds > 0) {
              bareruby_board_delay_us((uint32_t)microseconds);
          }
      }

      void bareruby_sleep(int32_t seconds) {
          if (seconds > 0) {
              HAL_Delay((uint32_t)seconds * 1000u);
          }
      }

      void bareruby_sleep_ms(int32_t milliseconds) {
          if (milliseconds > 0) {
              HAL_Delay((uint32_t)milliseconds);
          }
      }

      static uint32_t bareruby_asleep_mark;

      static void bareruby_asleep_until(uint32_t interval) {
          uint32_t now = HAL_GetTick();
          uint32_t deadline = bareruby_asleep_mark + interval;
          int32_t remaining = (int32_t)(deadline - now);
          if (remaining > 0) {
              HAL_Delay((uint32_t)remaining);
          }
          bareruby_asleep_mark = HAL_GetTick();
      }

      void bareruby_asleep(int32_t seconds) {
          bareruby_asleep_until(seconds > 0 ? (uint32_t)seconds * 1000u : 0u);
      }

      void bareruby_asleep_ms(int32_t milliseconds) {
          bareruby_asleep_until(milliseconds > 0 ? (uint32_t)milliseconds : 0u);
      }

      void bareruby_asleep_us(int32_t microseconds) {
          bareruby_machine_delay_us(microseconds);
      }
    CPP

    UART_RECEIVE = <<~CPP
      #include "bareruby_binding.h"

      #include "bareruby_board.h"

      bareruby_string_t *bareruby_uart_read(
          bareruby_uart_t *self, bareruby_arena_t *arena, int32_t length) {
          bareruby_string_t *result = bareruby_string_new(arena, "");
          for (int32_t index = 0; index < length; ++index) {
              uint8_t byte;
              if (HAL_UART_Receive(
                      bareruby_board_uart(self->id), &byte, 1, HAL_MAX_DELAY) != HAL_OK) {
                  bareruby_board_fault();
              }
              bareruby_string_append_byte(result, byte);
          }
          return result;
      }

      bareruby_string_t *bareruby_uart_gets(bareruby_uart_t *self, bareruby_arena_t *arena) {
          bareruby_string_t *result = bareruby_string_new(arena, "");
          uint8_t byte;
          do {
              if (HAL_UART_Receive(
                      bareruby_board_uart(self->id), &byte, 1, HAL_MAX_DELAY) != HAL_OK) {
                  bareruby_board_fault();
              }
              bareruby_string_append_byte(result, byte);
          } while (byte != '\\n');
          return result;
      }
    CPP

    I2C = <<~CPP
      #include "bareruby_binding.h"

      #include "bareruby_board.h"

      static uint16_t bareruby_i2c_address(int32_t address) {
          if (address < 0 || address > 0x7f) {
              bareruby_board_fault();
          }
          return (uint16_t)((uint32_t)address << 1);
      }

      void bareruby_i2c_init(bareruby_i2c_t *self, int32_t id, int32_t frequency) {
          self->id = id;
          self->frequency = frequency;
          if (frequency <= 0) {
              bareruby_board_fault();
          }
          I2C_HandleTypeDef *bus = bareruby_board_i2c(id);
          if (bus->Init.ClockSpeed != (uint32_t)frequency) {
              if (HAL_I2C_DeInit(bus) != HAL_OK) {
                  bareruby_board_fault();
              }
              bus->Init.ClockSpeed = (uint32_t)frequency;
              if (HAL_I2C_Init(bus) != HAL_OK) {
                  bareruby_board_fault();
              }
          }
      }

      int32_t bareruby_i2c_write(
          bareruby_i2c_t *self, int32_t address, const char *bytes, int32_t length) {
          if (length < 0 || length > UINT16_MAX) {
              bareruby_board_fault();
          }
          HAL_StatusTypeDef status = HAL_I2C_Master_Transmit(
              bareruby_board_i2c(self->id), bareruby_i2c_address(address), (uint8_t *)bytes,
              (uint16_t)length, HAL_MAX_DELAY);
          return status == HAL_OK ? length : -1;
      }
    CPP

    I2C_READ = <<~CPP
      #include "bareruby_binding.h"

      #include "bareruby_board.h"

      static uint16_t bareruby_i2c_read_address(int32_t address) {
          if (address < 0 || address > 0x7f) {
              bareruby_board_fault();
          }
          return (uint16_t)((uint32_t)address << 1);
      }

      bareruby_string_t *bareruby_i2c_read(
          bareruby_i2c_t *self, bareruby_arena_t *arena, int32_t address, int32_t length,
          const char *outputs, int32_t output_length) {
          if (length < 0 || length > UINT16_MAX || output_length < 0 || output_length > 2) {
              bareruby_board_fault();
          }

          /* HAL receives into the result's own bytes, so a read costs the arena one
             string and nothing else — a temporary here would sit in the region until
             the block ends, since an arena frees nothing. The handle is built by hand,
             in the runtime's own order, because the runtime offers no way to size a
             string before writing it. */
          bareruby_string_t *result =
              (bareruby_string_t *)bareruby_arena_alloc(arena, (int32_t)sizeof(bareruby_string_t));
          result->arena = arena;
          result->capacity = length + 1;
          result->bytes = (char *)bareruby_arena_alloc(arena, result->capacity);
          result->length = length;
          result->bytes[length] = '\\0';

          uint8_t *bytes = (uint8_t *)result->bytes;
          I2C_HandleTypeDef *bus = bareruby_board_i2c(self->id);
          uint16_t device = bareruby_i2c_read_address(address);
          HAL_StatusTypeDef status;
          if (output_length == 0) {
              status = HAL_I2C_Master_Receive(
                  bus, device, bytes, (uint16_t)length, HAL_MAX_DELAY);
          } else {
              uint16_t memory = (uint8_t)outputs[0];
              uint16_t memory_size = I2C_MEMADD_SIZE_8BIT;
              if (output_length == 2) {
                  memory = (uint16_t)(((uint16_t)(uint8_t)outputs[0] << 8) | (uint8_t)outputs[1]);
                  memory_size = I2C_MEMADD_SIZE_16BIT;
              }
              status = HAL_I2C_Mem_Read(
                  bus, device, memory, memory_size, bytes, (uint16_t)length, HAL_MAX_DELAY);
          }
          if (status != HAL_OK) {
              bareruby_board_fault();
          }

          return result;
      }
    CPP

    ONBOARD_LED = <<~CPP
      #include "bareruby_binding.h"

      #include "bareruby_board.h"

      void bareruby_onboard_led_init(bareruby_onboard_led_t *self) {
          self->state = 0;
          bareruby_board_led_initialize();
      }

      void bareruby_onboard_led_write(bareruby_onboard_led_t *self, int32_t value) {
          self->state = (value != 0) ? 1 : 0;
          bareruby_board_led_write(self->state != 0);
      }

      void bareruby_onboard_led_on(bareruby_onboard_led_t *self) {
          bareruby_onboard_led_write(self, 1);
      }

      void bareruby_onboard_led_off(bareruby_onboard_led_t *self) {
          bareruby_onboard_led_write(self, 0);
      }
    CPP

    UART_FILE = "bareruby_binding_uart_stm32.cpp"
    GPIO_FILE = "bareruby_binding_gpio_stm32.cpp"
    PERIPHERAL_FILE = "bareruby_binding_stm32.cpp"
    UART_RECEIVE_FILE = "bareruby_binding_uart_receive_stm32.cpp"
    I2C_FILE = "bareruby_binding_i2c_stm32.cpp"
    I2C_READ_FILE = "bareruby_binding_i2c_read_stm32.cpp"
    ONBOARD_LED_FILE = "bareruby_binding_onboard_led_stm32.cpp"

    FILES = {
      GPIO_FILE => GPIO,
      UART_FILE => UART,
      PERIPHERAL_FILE => PERIPHERAL,
      UART_RECEIVE_FILE => UART_RECEIVE,
      I2C_FILE => I2C,
      I2C_READ_FILE => I2C_READ,
      ONBOARD_LED_FILE => ONBOARD_LED
    }.freeze

    # What a peripheral asks for by key, this binding answers with a file. The key is the
    # peripheral's word and the file is this side's, so neither has to know the other.
    UNITS = { onboard_led: ONBOARD_LED_FILE, gpio: GPIO_FILE, uart: UART_FILE,
              uart_receive: UART_RECEIVE_FILE, i2c: I2C_FILE, i2c_read: I2C_READ_FILE }.freeze

    # One file answers every machine, so what remains machine-bound is refusal: a board
    # whose manifest carries no LED refuses the OnboardLED unit here, before any C
    # exists to fail. The STM32446E-EVAL's official data wires its labelled LED as an
    # input, which is how a manifest comes to have no led and a program that never
    # touches it still builds.
    # A refusal here is the program's mistake, not this gem's, so it is said the way
    # the compiler says its own compile errors: the message, and status 10.
    def self.unit(key, machine)
      if key == :onboard_led
        board = Manifests.board(machine.key)
        unless board.led
          warn "error: #{board.key} has no onboard LED, so OnboardLED cannot be built " \
               "for it. Its manifest is #{board.path}."
          exit 10
        end
      end
      UNITS.fetch(key)
    end

    ALWAYS = [PERIPHERAL_FILE].freeze

    # The generated program owns main now — there is no external project to enter from,
    # so the unit is named for the program rather than for an entry point.
    PROGRAM_FILE = "bareruby_program.cpp"

    def self.key = :stm32cube

    def self.toolchain = Stm32CubeToolchain

    def self.flash = Stm32CubeFlash

    def self.build = Stm32CubeBuild

    def self.init = Stm32CubeInit
  end
end
