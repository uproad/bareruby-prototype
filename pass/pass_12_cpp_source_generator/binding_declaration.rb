# frozen_string_literal: true

require_relative "../../standard_library"
require_relative "native_declaration"

module BareRubyProt
  # The header every binding and the program itself include: the struct each peripheral
  # keeps its state in and the prototype of every function behind their methods.
  #
  # Nothing here is written down twice. The structs and the prototypes are derived from the
  # declaration files, so a peripheral is spelled in one place and this header is what that
  # spelling looks like in C. What remains written out is what belongs to no class — the
  # startup a program runs before anything else, and the waits, which are reached without a
  # receiver.
  module BindingDeclaration
    PREAMBLE = <<~CPP
      #ifndef BARERUBY_BINDING_H
      #define BARERUBY_BINDING_H

      #include <stdbool.h>
      #include <stdint.h>
      #include "bareruby_runtime.h"

      #ifdef __cplusplus
      extern "C" {
      #endif
    CPP

    # sleep waits from the moment it is called, so a loop drifts by however long its body
    # takes. asleep waits from the moment the previous asleep returned, which is what a loop
    # that has to keep a period needs.
    BARE_FUNCTIONS = <<~CPP
      void bareruby_startup(void);

      void bareruby_machine_delay_us(int32_t microseconds);
      void bareruby_sleep(int32_t seconds);
      void bareruby_sleep_ms(int32_t milliseconds);
      void bareruby_asleep(int32_t seconds);
      void bareruby_asleep_ms(int32_t milliseconds);
      void bareruby_asleep_us(int32_t microseconds);
    CPP

    CLOSER = <<~CPP
      #ifdef __cplusplus
      }
      #endif

      #endif
    CPP

    HEADER_FILE = "bareruby_binding.h"

    def self.header
      declared = StandardLibrary.classes.values.map { |standard_class| NativeDeclaration.new(standard_class) }
      parts = [PREAMBLE] + declared.map { |declaration| "#{declaration.struct}\n" } +
              [BARE_FUNCTIONS] +
              declared.map { |declaration| "#{declaration.functions.join("\n")}\n" } +
              [CLOSER]
      parts.join("\n")
    end

    def self.files = { HEADER_FILE => header }
  end
end
