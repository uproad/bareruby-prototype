# frozen_string_literal: true

module BareRubyProt
  module Stm32CubeBinding
    # GPIO in its own translation unit. **A peripheral that can be uninstalled cannot
    # share a file with one that cannot** — the declarations go with the gem, and an
    # implementation left behind would have nothing to implement against.
    UART = <<~CPP
      #include "bareruby_binding.h"
      #include <stdarg.h>
      #include <stdio.h>
      #include <string.h>
      #include "main.h"
      #include "usart.h"

      static UART_HandleTypeDef *bareruby_uart_port(const bareruby_uart_t *self) {
          if (self->id != 0) {
              Error_Handler();
          }
          return &huart2;
      }

      void bareruby_uart_init(bareruby_uart_t *self, int32_t id, int32_t baud, int32_t parity) {
          self->id = id;
          self->baud = baud;
          self->parity = parity;
          UART_HandleTypeDef *port = bareruby_uart_port(self);
          uint32_t hal_parity = UART_PARITY_NONE;
          if (parity == 1) {
              hal_parity = UART_PARITY_EVEN;
          } else if (parity == 2) {
              hal_parity = UART_PARITY_ODD;
          } else if (parity != 0) {
              Error_Handler();
          }

          uint32_t word_length = hal_parity == UART_PARITY_NONE ? UART_WORDLENGTH_8B : UART_WORDLENGTH_9B;
          if (port->Init.BaudRate != (uint32_t)baud || port->Init.Parity != hal_parity ||
              port->Init.WordLength != word_length) {
              if (HAL_UART_DeInit(port) != HAL_OK) {
                  Error_Handler();
              }
              port->Init.BaudRate = (uint32_t)baud;
              port->Init.WordLength = word_length;
              port->Init.StopBits = UART_STOPBITS_1;
              port->Init.Parity = hal_parity;
              port->Init.Mode = UART_MODE_TX_RX;
              port->Init.HwFlowCtl = UART_HWCONTROL_NONE;
              port->Init.OverSampling = UART_OVERSAMPLING_16;
              if (HAL_UART_Init(port) != HAL_OK) {
                  Error_Handler();
              }
          }
      }

      int32_t bareruby_uart_write(bareruby_uart_t *self, const char *value) {
          int32_t length = (int32_t)strlen(value);
          HAL_StatusTypeDef status = HAL_UART_Transmit(
              bareruby_uart_port(self), (uint8_t *)value, (uint16_t)length, HAL_MAX_DELAY);
          return status == HAL_OK ? length : -1;
      }

      void bareruby_uart_puts(bareruby_uart_t *self, const char *value) {
          (void)bareruby_uart_write(self, value);
          static uint8_t newline = '\\n';
          (void)HAL_UART_Transmit(bareruby_uart_port(self), &newline, 1, HAL_MAX_DELAY);
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
              bareruby_uart_port(self), (uint8_t *)payload, transmitted, HAL_MAX_DELAY);
      }

      int32_t bareruby_uart_bytes_available(bareruby_uart_t *self) {
          return __HAL_UART_GET_FLAG(bareruby_uart_port(self), UART_FLAG_RXNE) != RESET ? 1 : 0;
      }

      bool bareruby_uart_can_read_line(bareruby_uart_t *self) {
          return bareruby_uart_bytes_available(self) != 0;
      }

      void bareruby_uart_flush(bareruby_uart_t *self) {
          UART_HandleTypeDef *port = bareruby_uart_port(self);
          while (__HAL_UART_GET_FLAG(port, UART_FLAG_TC) == RESET) {
          }
      }

      void bareruby_uart_clear_rx_buffer(bareruby_uart_t *self) {
          UART_HandleTypeDef *port = bareruby_uart_port(self);
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
      #include <stdarg.h>
      #include <stdio.h>
      #include <string.h>
      #include "main.h"
      #include "usart.h"

      static GPIO_TypeDef *bareruby_gpio_port(int32_t pin) {
          switch (pin / 16) {
          case 0: return GPIOA;
          case 1: return GPIOB;
          case 2: return GPIOC;
          case 3: return GPIOD;
          case 4: return GPIOE;
          case 5: return GPIOF;
          case 6: return GPIOG;
          case 7: return GPIOH;
          default: Error_Handler(); return GPIOA;
          }
      }

      static uint16_t bareruby_gpio_pin(int32_t pin) {
          if (pin < 0 || pin >= 128) {
              Error_Handler();
          }
          return (uint16_t)(1u << ((uint32_t)pin & 15u));
      }

      static void bareruby_gpio_enable_clock(int32_t pin) {
          switch (pin / 16) {
          case 0: __HAL_RCC_GPIOA_CLK_ENABLE(); break;
          case 1: __HAL_RCC_GPIOB_CLK_ENABLE(); break;
          case 2: __HAL_RCC_GPIOC_CLK_ENABLE(); break;
          case 3: __HAL_RCC_GPIOD_CLK_ENABLE(); break;
          case 4: __HAL_RCC_GPIOE_CLK_ENABLE(); break;
          case 5: __HAL_RCC_GPIOF_CLK_ENABLE(); break;
          case 6: __HAL_RCC_GPIOG_CLK_ENABLE(); break;
          case 7: __HAL_RCC_GPIOH_CLK_ENABLE(); break;
          default: Error_Handler();
          }
      }

      void bareruby_gpio_init(bareruby_gpio_t *self, int32_t pin, int32_t params) {
          self->pin = pin;
          self->params = params;
          bareruby_gpio_enable_clock(pin);

          GPIO_InitTypeDef config = {};
          config.Pin = bareruby_gpio_pin(pin);
          config.Pull = (params & 8) ? GPIO_PULLUP : ((params & 16) ? GPIO_PULLDOWN : GPIO_NOPULL);
          config.Speed = GPIO_SPEED_FREQ_LOW;
          if (params & 2) {
              config.Mode = (params & 32) ? GPIO_MODE_OUTPUT_OD : GPIO_MODE_OUTPUT_PP;
          } else {
              config.Mode = GPIO_MODE_INPUT;
          }
          HAL_GPIO_Init(bareruby_gpio_port(pin), &config);
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
    CPP

    PERIPHERAL = <<~CPP
      #include "bareruby_binding.h"

      #include <stdarg.h>
      #include <stdio.h>
      #include <string.h>

      #include "main.h"
      #include "usart.h"


      extern "C" int __io_putchar(int ch) {
          uint8_t byte = (uint8_t)ch;
          return HAL_UART_Transmit(&huart2, &byte, 1, HAL_MAX_DELAY) == HAL_OK ? ch : EOF;
      }

      void bareruby_startup(void) {
          // HAL_Init, the system clock, and all MX peripherals are ready before entry.
      }

      static void bareruby_delay_us(uint32_t microseconds) {
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

      void bareruby_machine_delay_us(int32_t microseconds) {
          if (microseconds > 0) {
              bareruby_delay_us((uint32_t)microseconds);
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

      #include "main.h"
      #include "usart.h"

      static UART_HandleTypeDef *bareruby_uart_receive_port(const bareruby_uart_t *self) {
          if (self->id != 0) {
              Error_Handler();
          }
          return &huart2;
      }

      bareruby_string_t *bareruby_uart_read(
          bareruby_uart_t *self, bareruby_arena_t *arena, int32_t length) {
          bareruby_string_t *result = bareruby_string_new(arena, "");
          for (int32_t index = 0; index < length; ++index) {
              uint8_t byte;
              if (HAL_UART_Receive(
                      bareruby_uart_receive_port(self), &byte, 1, HAL_MAX_DELAY) != HAL_OK) {
                  Error_Handler();
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
                      bareruby_uart_receive_port(self), &byte, 1, HAL_MAX_DELAY) != HAL_OK) {
                  Error_Handler();
              }
              bareruby_string_append_byte(result, byte);
          } while (byte != '\\n');
          return result;
      }
    CPP

    I2C = <<~CPP
      #include "bareruby_binding.h"

      #include "i2c.h"
      #include "main.h"

      static I2C_HandleTypeDef *bareruby_i2c_port(const bareruby_i2c_t *self) {
          if (self->id != 1) {
              Error_Handler();
          }
          return &hi2c1;
      }

      static uint16_t bareruby_i2c_address(int32_t address) {
          if (address < 0 || address > 0x7f) {
              Error_Handler();
          }
          return (uint16_t)((uint32_t)address << 1);
      }

      void bareruby_i2c_init(bareruby_i2c_t *self, int32_t id, int32_t frequency) {
          self->id = id;
          self->frequency = frequency;
          if (frequency <= 0) {
              Error_Handler();
          }
          I2C_HandleTypeDef *port = bareruby_i2c_port(self);
          if (port->Init.ClockSpeed != (uint32_t)frequency) {
              if (HAL_I2C_DeInit(port) != HAL_OK) {
                  Error_Handler();
              }
              port->Init.ClockSpeed = (uint32_t)frequency;
              if (HAL_I2C_Init(port) != HAL_OK) {
                  Error_Handler();
              }
          }
      }

      int32_t bareruby_i2c_write(
          bareruby_i2c_t *self, int32_t address, const char *bytes, int32_t length) {
          if (length < 0 || length > UINT16_MAX) {
              Error_Handler();
          }
          HAL_StatusTypeDef status = HAL_I2C_Master_Transmit(
              bareruby_i2c_port(self), bareruby_i2c_address(address), (uint8_t *)bytes,
              (uint16_t)length, HAL_MAX_DELAY);
          return status == HAL_OK ? length : -1;
      }
    CPP

    I2C_READ = <<~CPP
      #include "bareruby_binding.h"

      #include "i2c.h"
      #include "main.h"

      static I2C_HandleTypeDef *bareruby_i2c_read_port(const bareruby_i2c_t *self) {
          if (self->id != 1) {
              Error_Handler();
          }
          return &hi2c1;
      }

      static uint16_t bareruby_i2c_read_address(int32_t address) {
          if (address < 0 || address > 0x7f) {
              Error_Handler();
          }
          return (uint16_t)((uint32_t)address << 1);
      }

      bareruby_string_t *bareruby_i2c_read(
          bareruby_i2c_t *self, bareruby_arena_t *arena, int32_t address, int32_t length,
          const char *outputs, int32_t output_length) {
          if (length < 0 || length > UINT16_MAX || output_length < 0 || output_length > 2) {
              Error_Handler();
          }

          uint8_t *bytes = (uint8_t *)bareruby_arena_alloc(arena, length);
          I2C_HandleTypeDef *port = bareruby_i2c_read_port(self);
          uint16_t device = bareruby_i2c_read_address(address);
          HAL_StatusTypeDef status;
          if (output_length == 0) {
              status = HAL_I2C_Master_Receive(
                  port, device, bytes, (uint16_t)length, HAL_MAX_DELAY);
          } else {
              uint16_t memory = (uint8_t)outputs[0];
              uint16_t memory_size = I2C_MEMADD_SIZE_8BIT;
              if (output_length == 2) {
                  memory = (uint16_t)(((uint16_t)(uint8_t)outputs[0] << 8) | (uint8_t)outputs[1]);
                  memory_size = I2C_MEMADD_SIZE_16BIT;
              }
              status = HAL_I2C_Mem_Read(
                  port, device, memory, memory_size, bytes, (uint16_t)length, HAL_MAX_DELAY);
          }
          if (status != HAL_OK) {
              Error_Handler();
          }

          bareruby_string_t *result = bareruby_string_new(arena, "");
          return bareruby_string_append_bytes(result, (const char *)bytes, length);
      }
    CPP

    UART_FILE = "bareruby_binding_uart_stm32.cpp"
    GPIO_FILE = "bareruby_binding_gpio_stm32.cpp"
    PERIPHERAL_FILE = "bareruby_binding_stm32.cpp"
    UART_RECEIVE_FILE = "bareruby_binding_uart_receive_stm32.cpp"
    I2C_FILE = "bareruby_binding_i2c_stm32.cpp"
    I2C_READ_FILE = "bareruby_binding_i2c_read_stm32.cpp"

    # LD2 is on a pin, and which pin is the CubeMX project's answer: it defines
    # LD2_GPIO_Port and LD2_Pin, so a board that puts its LED elsewhere needs no
    # change here. Reaching it is the same mechanism a Pico uses, spelled in HAL.
    ONBOARD_LED_PIN = <<~CPP
      #include "bareruby_binding.h"

      #include "main.h"

      void bareruby_onboard_led_init(bareruby_onboard_led_t *self) {
          self->state = 0;
          HAL_GPIO_WritePin(LD2_GPIO_Port, LD2_Pin, GPIO_PIN_RESET);
      }

      void bareruby_onboard_led_write(bareruby_onboard_led_t *self, int32_t value) {
          self->state = (value != 0) ? 1 : 0;
          HAL_GPIO_WritePin(
              LD2_GPIO_Port, LD2_Pin, self->state != 0 ? GPIO_PIN_SET : GPIO_PIN_RESET);
      }

      void bareruby_onboard_led_on(bareruby_onboard_led_t *self) {
          bareruby_onboard_led_write(self, 1);
      }

      void bareruby_onboard_led_off(bareruby_onboard_led_t *self) {
          bareruby_onboard_led_write(self, 0);
      }
    CPP

    ONBOARD_LED_PIN_FILE = "bareruby_binding_onboard_led_stm32cube_pin.cpp"

    FILES = {
      GPIO_FILE => GPIO,
      UART_FILE => UART,
      PERIPHERAL_FILE => PERIPHERAL,
      UART_RECEIVE_FILE => UART_RECEIVE,
      I2C_FILE => I2C,
      I2C_READ_FILE => I2C_READ,
      ONBOARD_LED_PIN_FILE => ONBOARD_LED_PIN
    }.freeze
    # What a peripheral asks for by key, this binding answers with a file. The key is the
    # peripheral's word and the file is this side's, so neither has to know the other.
    UNITS = { onboard_led: :onboard_led_file, gpio: GPIO_FILE, uart: UART_FILE, uart_receive: UART_RECEIVE_FILE, i2c: I2C_FILE, i2c_read: I2C_READ_FILE }.freeze

    # A unit is usually one file. **Some are the machine's answer instead** — an
    # indicator is reached through a pin on one board and through a radio on another, so
    # the key resolves to a question rather than a name, and the cell beside this file
    # answers it.
    def self.unit(key, machine)
      found = UNITS.fetch(key)
      found.is_a?(Symbol) ? machine(machine).public_send(found) : found
    end

    ALWAYS = [PERIPHERAL_FILE].freeze


    # What a machine takes is not worked out here. Each machine this binding reaches
    # writes its own answer as a method, in machine/ beside this file, and this only hands
    # the question over. A machine it cannot reach has no answer rather than a wrong one.
    MACHINES = {}

    def self.machine(machine) = MACHINES.fetch(machine.key)

    # The CubeMX project owns main and calls into the program, so this side names its
    # translation unit after the program rather than after an entry point it does not own.
    PROGRAM_FILE = "bareruby_program.cpp"

    def self.key = :stm32cube

    def self.toolchain = Stm32CubeToolchain

    def self.flash = Stm32CubeFlash

    def self.build = Stm32CubeBuild
  end
end

# One machine to a file, so that teaching this binding a new machine is adding a file.
Dir.children(File.expand_path("machine", __dir__)).sort.grep(/\.rb\z/).each do |entry|
  require_relative "machine/#{entry}"
end
