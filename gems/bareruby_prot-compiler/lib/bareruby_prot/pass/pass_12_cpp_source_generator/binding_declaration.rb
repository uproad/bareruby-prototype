# frozen_string_literal: true

module BareRubyProt
  module BindingDeclaration
    HEADER = <<~CPP
      #ifndef BARERUBY_BINDING_H
      #define BARERUBY_BINDING_H

      #include <stdbool.h>
      #include <stdint.h>
      #include "bareruby_runtime.h"

      #ifdef __cplusplus
      extern "C" {
      #endif

      typedef void (*bareruby_interrupt_handler_t)(void);

      /* The borrowed string a handler is handed: a pointer and a length into bytes the
         binding owns, valid for the handler and no longer. The comparison lives here,
         outside the bareruby_string_ runtime family, so that comparing a view never
         links the string runtime or the arena. */
      typedef struct {
          const char *bytes;
          int32_t length;
      } bareruby_string_view_t;

      static inline bool bareruby_text_view_equal(
          const bareruby_string_view_t *self, const char *value) {
          int32_t index = 0;
          while (index < self->length && value[index] != '\\0') {
              if (self->bytes[index] != value[index]) {
                  return false;
              }
              ++index;
          }
          return index == self->length && value[index] == '\\0';
      }

      void bareruby_startup(void);

      void bareruby_machine_delay_us(int32_t microseconds);
      void bareruby_sleep(int32_t seconds);
      void bareruby_sleep_ms(int32_t milliseconds);
      void bareruby_asleep(int32_t seconds);
      void bareruby_asleep_ms(int32_t milliseconds);
      void bareruby_asleep_us(int32_t microseconds);
      int32_t bareruby_ticks_ms(void);

      #ifdef __cplusplus
      }
      #endif

      #endif
    CPP

    HEADER_FILE = "bareruby_binding.h"

    # The declarations a peripheral brought with it go **last**, after everything this side
    # declares. They may use a type named here — a handler's signature does — while nothing
    # here can use a type of theirs, so the order is not a preference but the only one that
    # compiles. The guard opens with `extern "C" {` and closes with `}`, and it is the
    # closing pair that this lands in front of.
    #
    # A peripheral that is not installed declares nothing, and a binding that implements it
    # anyway has nothing to implement against — which is the point: **the header says what
    # this build knows about, and nothing else.**
    CLOSING = /^\#ifdef __cplusplus\n\}\n/

    def self.header
      registered = Peripheral.declarations
      return HEADER if registered.empty?

      HEADER.sub(CLOSING) { |closing| "#{registered.join("\n\n")}\n\n#{closing}" }
    end

    def self.files = { HEADER_FILE => header }
  end
end
