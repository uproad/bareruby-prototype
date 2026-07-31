# frozen_string_literal: true

module BareRubyProt
  module Stm32BindingSource
    PERIPHERAL = <<~CPP
      #include "bareruby_binding.h"

      #include "main.h"

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

      void bareruby_startup(void) {
          // HAL_Init, the system clock, and all MX peripherals are ready before entry.
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

    PERIPHERAL_FILE = "bareruby_binding_stm32.cpp"
    UART_RECEIVE_FILE = "bareruby_binding_uart_receive_stm32.cpp"
    I2C_FILE = "bareruby_binding_i2c_stm32.cpp"
    I2C_READ_FILE = "bareruby_binding_i2c_read_stm32.cpp"

    FILES = { PERIPHERAL_FILE => PERIPHERAL }.freeze
    ALWAYS = [PERIPHERAL_FILE].freeze
  end
end
