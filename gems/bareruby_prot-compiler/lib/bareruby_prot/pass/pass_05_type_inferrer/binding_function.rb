# frozen_string_literal: true

module BareRubyProt
  # What the binding layer offers that is not a piece of hardware: the waits, reached
  # without a receiver or through a module. sleep waits from the moment it is called, so a
  # loop drifts by however long its body takes; asleep waits from the moment the previous
  # asleep returned, which is what a loop that has to keep a period needs.
  module BindingFunction
    BARE = {
      sleep: { function: :bareruby_sleep, parameter_types: %i[Int32], return_type: :Nil },
      sleep_ms: { function: :bareruby_sleep_ms, parameter_types: %i[Int32], return_type: :Nil },
      asleep: { function: :bareruby_asleep, parameter_types: %i[Int32], return_type: :Nil },
      asleep_ms: { function: :bareruby_asleep_ms, parameter_types: %i[Int32], return_type: :Nil },
      asleep_us: { function: :bareruby_asleep_us, parameter_types: %i[Int32], return_type: :Nil }
    }.freeze

    MODULES = {
      Machine: {
        delay_us: { function: :bareruby_machine_delay_us, parameter_types: %i[Int32], return_type: :Nil }
      }
    }.freeze

    def self.bare?(name) = BARE.key?(name)

    def self.bare(name) = BARE.fetch(name)

    def self.module?(name) = MODULES.key?(name)

    def self.of_module(module_name, name) = MODULES.fetch(module_name).fetch(name)
  end
end
