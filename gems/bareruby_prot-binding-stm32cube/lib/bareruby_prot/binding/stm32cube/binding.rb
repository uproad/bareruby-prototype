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

      void bareruby_uart_init(
          bareruby_uart_t *self, int32_t id, int32_t baud,
          int32_t data_bits, int32_t stop_bits, int32_t parity) {
          self->id = id;
          self->baud = baud;
          self->data_bits = data_bits;
          self->stop_bits = stop_bits;
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
          uint32_t hal_stop_bits = stop_bits == 2 ? UART_STOPBITS_2 : UART_STOPBITS_1;

          /* **On an F4 the word length counts the parity bit.** So the frame this device
             can produce is the sum of the two, and only 8 and 9 exist -- UART_WORDLENGTH_7B
             arrives with the L4 / G4 / F7 generations, not here. 7E1 is therefore an 8-bit
             word with parity on, and 7N1, 6 and 5 have no spelling at all. A frame this
             device cannot produce is refused rather than replaced. */
          int32_t frame_bits = data_bits + (hal_parity == UART_PARITY_NONE ? 0 : 1);
          if (frame_bits != 8 && frame_bits != 9) {
              bareruby_board_fault();
          }
          uint32_t word_length = frame_bits == 8 ? UART_WORDLENGTH_8B : UART_WORDLENGTH_9B;
          if (port->Init.BaudRate != (uint32_t)baud || port->Init.Parity != hal_parity ||
              port->Init.WordLength != word_length || port->Init.StopBits != hal_stop_bits) {
              if (HAL_UART_DeInit(port) != HAL_OK) {
                  bareruby_board_fault();
              }
              port->Init.BaudRate = (uint32_t)baud;
              port->Init.WordLength = word_length;
              port->Init.StopBits = hal_stop_bits;
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

      /* Weak, so the uart_interrupt unit's ring-backed answer replaces this one the
         moment a program touches the buffered receive side. */
      __attribute__((weak)) int32_t bareruby_uart_bytes_available(bareruby_uart_t *self) {
          return __HAL_UART_GET_FLAG(bareruby_board_uart(self->id), UART_FLAG_RXNE) != RESET ? 1 : 0;
      }

      /* The HAL transmits by blocking, so nothing is queued behind the call. What can
         still be owed is the frame in the shift register: TC falls while it goes out. */
      int32_t bareruby_uart_bytes_to_write(bareruby_uart_t *self) {
          UART_HandleTypeDef *port = bareruby_board_uart(self->id);
          return __HAL_UART_GET_FLAG(port, UART_FLAG_TC) == RESET ? 1 : 0;
      }

      /* **SBK sends exactly one break character**, and an F4 has no bit that holds the
         line low for an arbitrary span. So the requested time is served by sending break
         characters until it has passed -- the line is low for very nearly the whole of
         it, with one character's worth of idle between. */
      void bareruby_uart_send_break(bareruby_uart_t *self, int32_t milliseconds) {
          UART_HandleTypeDef *port = bareruby_board_uart(self->id);
          bareruby_uart_flush(self);
          uint32_t deadline = HAL_GetTick() + (uint32_t)(milliseconds > 0 ? milliseconds : 0);
          do {
              port->Instance->CR1 |= USART_CR1_SBK;
              while ((port->Instance->CR1 & USART_CR1_SBK) != 0u) {
              }
          } while ((int32_t)(deadline - HAL_GetTick()) > 0);
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

      /* The uart_interrupt unit overrides this when a program says on_line; otherwise
         sleep drains nothing and pays one empty call per millisecond. */
      extern "C" __attribute__((weak)) void bareruby_uart_interrupt_drain(void) {}

      void bareruby_machine_delay_us(int32_t microseconds) {
          if (microseconds > 0) {
              bareruby_board_delay_us((uint32_t)microseconds);
          }
      }

      /* The wait is counted unsigned, as the asleep mark below is, so that the seconds
         form can turn its argument into milliseconds without overflowing a signed
         multiplication. */
      static void bareruby_sleep_for(uint32_t milliseconds, bool interrupt) {
          uint32_t deadline = HAL_GetTick() + milliseconds;
          for (;;) {
              if (interrupt) {
                  bareruby_uart_interrupt_drain();
              }
              if ((int32_t)(deadline - HAL_GetTick()) <= 0) {
                  break;
              }
              HAL_Delay(1);
          }
      }

      void bareruby_sleep_ms(int32_t milliseconds, bool interrupt) {
          bareruby_sleep_for(milliseconds > 0 ? (uint32_t)milliseconds : 0u, interrupt);
      }

      void bareruby_sleep(int32_t seconds, bool interrupt) {
          bareruby_sleep_for(seconds > 0 ? (uint32_t)seconds * 1000u : 0u, interrupt);
      }

      static uint32_t bareruby_asleep_mark;

      /* The tick this mark is kept in counts milliseconds, so the whole wait is spent in
         them and delivering costs the period nothing it did not already cost. */
      static void bareruby_asleep_until(uint32_t interval, bool interrupt) {
          uint32_t deadline = bareruby_asleep_mark + interval;
          while (interrupt && (int32_t)(deadline - HAL_GetTick()) > 0) {
              bareruby_uart_interrupt_drain();
              HAL_Delay(1);
          }
          int32_t remaining = (int32_t)(deadline - HAL_GetTick());
          if (remaining > 0) {
              HAL_Delay((uint32_t)remaining);
          }
          bareruby_asleep_mark = HAL_GetTick();
      }

      void bareruby_asleep(int32_t seconds, bool interrupt) {
          bareruby_asleep_until(seconds > 0 ? (uint32_t)seconds * 1000u : 0u, interrupt);
      }

      void bareruby_asleep_ms(int32_t milliseconds, bool interrupt) {
          bareruby_asleep_until(milliseconds > 0 ? (uint32_t)milliseconds : 0u, interrupt);
      }

      /* **This one delivers nothing, whatever it is asked for.** It does not go through
         the wait above at all: it delays microseconds directly and never moves the mark
         the other two keep their period by, which is a fault of its own and is being
         tracked as one. Until that is settled there is no loop here to deliver in. */
      void bareruby_asleep_us(int32_t microseconds, bool interrupt) {
          (void)interrupt;
          bareruby_machine_delay_us(microseconds);
      }

      int32_t bareruby_ticks_ms(void) {
          return (int32_t)HAL_GetTick();
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

    # The receive interrupt. The ISR does one thing — push the received byte into a
    # 256-byte ring — and every policy (LF/CRLF framing, the 255-byte cap, the overlong
    # discard, the handler itself) runs in thread mode when sleep drains the ring. One
    # producer, one consumer, single-byte indices that wrap by uint8_t overflow: no
    # critical section is needed on a Cortex-M4. HAL's own IRQ machinery serves
    # HAL_UART_Receive_IT, which this unit does not use, so the vectors read SR and DR
    # directly — on an F4 that one sequence also clears RXNE and ORE.
    UART_INTERRUPT = <<~CPP
      #include "bareruby_binding.h"

      #include "bareruby_board.h"

      typedef struct {
          volatile uint8_t data[256];   /* the 256 bytes on_line costs; ISR writes, drain reads */
          volatile uint8_t head;        /* ISR-owned */
          volatile uint8_t tail;        /* drain-owned */
          char line[256];               /* the view a handler is handed points here */
          int32_t line_length;
          bool discarding;              /* an overlong line, thrown away to the next LF */
          bareruby_uart_line_handler_t handler;
          UART_HandleTypeDef *port;
      } bareruby_uart_interrupt_t;

      static bareruby_uart_interrupt_t bareruby_uart_interrupt;

      static void bareruby_uart_interrupt_push(uint8_t byte) {
          uint8_t next = (uint8_t)(bareruby_uart_interrupt.head + 1u);
          if (next == bareruby_uart_interrupt.tail) {
              return;   /* a full ring drops the byte */
          }
          bareruby_uart_interrupt.data[bareruby_uart_interrupt.head] = byte;
          bareruby_uart_interrupt.head = next;
      }

      static void bareruby_uart_interrupt_service(void) {
          UART_HandleTypeDef *port = bareruby_uart_interrupt.port;
          if (port == NULL) {
              return;
          }
          uint32_t status = port->Instance->SR;
          if (status & (USART_SR_RXNE | USART_SR_ORE)) {
              uint8_t byte = (uint8_t)(port->Instance->DR & 0xFFu);
              /* A byte whose parity failed is discarded, as Arduino's core does. */
              if ((status & USART_SR_PE) == 0u) {
                  bareruby_uart_interrupt_push(byte);
              }
          }
      }

      /* Strong handlers replacing the startup file's weak defaults — the same move the
         GPIO unit makes for the seven EXTI vectors. Only the registered port raises its
         IRQ, so they may all share one service. Which instances exist is the device
         header's answer; an F401 has no USART3, UART4 or UART5. */
      extern "C" void USART1_IRQHandler(void) { bareruby_uart_interrupt_service(); }
      extern "C" void USART2_IRQHandler(void) { bareruby_uart_interrupt_service(); }
      #if defined(USART3)
      extern "C" void USART3_IRQHandler(void) { bareruby_uart_interrupt_service(); }
      #endif
      #if defined(UART4)
      extern "C" void UART4_IRQHandler(void) { bareruby_uart_interrupt_service(); }
      #endif
      #if defined(UART5)
      extern "C" void UART5_IRQHandler(void) { bareruby_uart_interrupt_service(); }
      #endif
      #if defined(USART6)
      extern "C" void USART6_IRQHandler(void) { bareruby_uart_interrupt_service(); }
      #endif

      static IRQn_Type bareruby_uart_interrupt_irq(USART_TypeDef *instance) {
          if (instance == USART1) return USART1_IRQn;
      #if defined(USART3)
          if (instance == USART3) return USART3_IRQn;
      #endif
      #if defined(UART4)
          if (instance == UART4) return UART4_IRQn;
      #endif
      #if defined(UART5)
          if (instance == UART5) return UART5_IRQn;
      #endif
      #if defined(USART6)
          if (instance == USART6) return USART6_IRQn;
      #endif
          return USART2_IRQn;
      }

      static void bareruby_uart_interrupt_line_byte(uint8_t byte) {
          if (byte == '\\n') {
              if (bareruby_uart_interrupt.discarding) {
                  bareruby_uart_interrupt.discarding = false;
                  bareruby_uart_interrupt.line_length = 0;
                  return;
              }
              int32_t length = bareruby_uart_interrupt.line_length;
              if (length > 0 && bareruby_uart_interrupt.line[length - 1] == '\\r') {
                  length -= 1;
              }
              bareruby_uart_interrupt.line[length] = '\\0';
              bareruby_uart_interrupt.line_length = 0;
              if (bareruby_uart_interrupt.handler != NULL) {
                  bareruby_string_view_t view = {bareruby_uart_interrupt.line, length};
                  bareruby_uart_interrupt.handler(&view);
              }
              return;
          }
          if (bareruby_uart_interrupt.discarding) {
              return;
          }
          if (bareruby_uart_interrupt.line_length == 255) {   /* a line is at most 255 bytes */
              bareruby_uart_interrupt.discarding = true;
              bareruby_uart_interrupt.line_length = 0;
              return;
          }
          bareruby_uart_interrupt.line[bareruby_uart_interrupt.line_length++] = (char)byte;
      }

      /* The ring has one consumer. A registered handler is it, and the drain assembles
         lines; without one the bytes wait for the read family below. */
      extern "C" void bareruby_uart_interrupt_drain(void) {
          if (bareruby_uart_interrupt.handler == NULL) {
              return;
          }
          while (bareruby_uart_interrupt.tail != bareruby_uart_interrupt.head) {
              uint8_t byte = bareruby_uart_interrupt.data[bareruby_uart_interrupt.tail];
              bareruby_uart_interrupt.tail = (uint8_t)(bareruby_uart_interrupt.tail + 1u);
              bareruby_uart_interrupt_line_byte(byte);
          }
      }

      /* The first touch of the receive side — a registration or a buffered read — is
         what arms the interrupt and so what buys the ring. */
      static void bareruby_uart_interrupt_attach(bareruby_uart_t *self) {
          if (bareruby_uart_interrupt.port != NULL) {
              return;
          }
          UART_HandleTypeDef *port = bareruby_board_uart(self->id);
          bareruby_uart_interrupt.port = port;   /* published before the IRQ can fire */
          IRQn_Type interrupt = bareruby_uart_interrupt_irq(port->Instance);

          /* A byte left over from before the arming is not received data. Priority 2
             matches the GPIO EXTI precedent. */
          __HAL_UART_FLUSH_DRREGISTER(port);
          __HAL_UART_ENABLE_IT(port, UART_IT_RXNE);
          HAL_NVIC_ClearPendingIRQ(interrupt);
          HAL_NVIC_SetPriority(interrupt, 2, 0);
          HAL_NVIC_EnableIRQ(interrupt);
      }

      void bareruby_uart_on_line(bareruby_uart_t *self, bareruby_uart_line_handler_t handler) {
          bareruby_uart_interrupt.handler = handler;
          bareruby_uart_interrupt_attach(self);
      }

      int32_t bareruby_uart_read_byte(bareruby_uart_t *self) {
          bareruby_uart_interrupt_attach(self);
          if (bareruby_uart_interrupt.tail == bareruby_uart_interrupt.head) {
              return -1;
          }
          uint8_t byte = bareruby_uart_interrupt.data[bareruby_uart_interrupt.tail];
          bareruby_uart_interrupt.tail = (uint8_t)(bareruby_uart_interrupt.tail + 1u);
          return (int32_t)byte;
      }

      int32_t bareruby_uart_peek(bareruby_uart_t *self) {
          bareruby_uart_interrupt_attach(self);
          if (bareruby_uart_interrupt.tail == bareruby_uart_interrupt.head) {
              return -1;
          }
          return (int32_t)bareruby_uart_interrupt.data[bareruby_uart_interrupt.tail];
      }

      /* The strong definition; the polling one in the uart unit is weak. */
      int32_t bareruby_uart_bytes_available(bareruby_uart_t *self) {
          bareruby_uart_interrupt_attach(self);
          return (int32_t)(uint8_t)(bareruby_uart_interrupt.head - bareruby_uart_interrupt.tail);
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
    UART_INTERRUPT_FILE = "bareruby_binding_uart_interrupt_stm32.cpp"
    I2C_FILE = "bareruby_binding_i2c_stm32.cpp"
    I2C_READ_FILE = "bareruby_binding_i2c_read_stm32.cpp"
    ONBOARD_LED_FILE = "bareruby_binding_onboard_led_stm32.cpp"

    FILES = {
      GPIO_FILE => GPIO,
      UART_FILE => UART,
      PERIPHERAL_FILE => PERIPHERAL,
      UART_RECEIVE_FILE => UART_RECEIVE,
      UART_INTERRUPT_FILE => UART_INTERRUPT,
      I2C_FILE => I2C,
      I2C_READ_FILE => I2C_READ,
      ONBOARD_LED_FILE => ONBOARD_LED
    }.freeze

    # What a peripheral asks for by key, this binding answers with a file. The key is the
    # peripheral's word and the file is this side's, so neither has to know the other.
    UNITS = { onboard_led: ONBOARD_LED_FILE, gpio: GPIO_FILE, uart: UART_FILE,
              uart_receive: UART_RECEIVE_FILE, uart_interrupt: UART_INTERRUPT_FILE,
              i2c: I2C_FILE, i2c_read: I2C_READ_FILE }.freeze

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
