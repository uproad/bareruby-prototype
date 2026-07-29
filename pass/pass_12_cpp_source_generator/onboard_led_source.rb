# frozen_string_literal: true

module BareRubyProt
  module OnboardLedSource
    # Three implementations of one interface, and which one a build links is the only
    # thing that changes. The program says `OnboardLED.new` on all of them.
    HOST = <<~CPP
      #include "bareruby_binding.h"

      #include <stdio.h>

      void bareruby_onboard_led_init(bareruby_onboard_led_t *self) {
          self->state = 0;
          fprintf(stderr, "onboard_led_init()\\n");
      }

      void bareruby_onboard_led_write(bareruby_onboard_led_t *self, int32_t value) {
          self->state = (value != 0) ? 1 : 0;
          fprintf(stderr, "onboard_led_write(value=%d)\\n", (int)self->state);
      }

      void bareruby_onboard_led_on(bareruby_onboard_led_t *self) {
          bareruby_onboard_led_write(self, 1);
      }

      void bareruby_onboard_led_off(bareruby_onboard_led_t *self) {
          bareruby_onboard_led_write(self, 0);
      }
    CPP

    # A board whose LED is on a pin of the microcontroller. Which pin is the board's
    # answer, not this file's: pico-sdk's board header defines PICO_DEFAULT_LED_PIN, so
    # a board that puts its LED somewhere else needs no change here.
    PIN = <<~CPP
      #include "bareruby_binding.h"

      #include "hardware/gpio.h"
      #include "pico/stdlib.h"

      void bareruby_onboard_led_init(bareruby_onboard_led_t *self) {
          self->state = 0;
          gpio_init(PICO_DEFAULT_LED_PIN);
          gpio_set_dir(PICO_DEFAULT_LED_PIN, GPIO_OUT);
      }

      void bareruby_onboard_led_write(bareruby_onboard_led_t *self, int32_t value) {
          self->state = (value != 0) ? 1 : 0;
          gpio_put(PICO_DEFAULT_LED_PIN, self->state != 0);
      }

      void bareruby_onboard_led_on(bareruby_onboard_led_t *self) {
          bareruby_onboard_led_write(self, 1);
      }

      void bareruby_onboard_led_off(bareruby_onboard_led_t *self) {
          bareruby_onboard_led_write(self, 0);
      }
    CPP

    # A wireless board's LED hangs off the radio, not off a pin, so reaching it means
    # bringing the CYW43 up first — the chip runs firmware that the host uploads, which
    # is what this costs. GP25, where the plain board's LED sits, is the radio's select
    # line on this one; writing it here would fight the driver rather than blink.
    WIRELESS = <<~CPP
      #include "bareruby_binding.h"

      #include "pico/cyw43_arch.h"

      void bareruby_onboard_led_init(bareruby_onboard_led_t *self) {
          self->state = 0;
          cyw43_arch_init();
      }

      void bareruby_onboard_led_write(bareruby_onboard_led_t *self, int32_t value) {
          self->state = (value != 0) ? 1 : 0;
          cyw43_arch_gpio_put(CYW43_WL_GPIO_LED_PIN, self->state != 0);
      }

      void bareruby_onboard_led_on(bareruby_onboard_led_t *self) {
          bareruby_onboard_led_write(self, 1);
      }

      void bareruby_onboard_led_off(bareruby_onboard_led_t *self) {
          bareruby_onboard_led_write(self, 0);
      }
    CPP

    # The on-board LED is the one peripheral whose implementation two boards of the same
    # chip disagree about, so it is split by the target's answer rather than by the kind
    # of machine. A build takes exactly one of the three.
    IMPLEMENTATIONS = {
      host: ["bareruby_binding_onboard_led_host.cpp", HOST],
      pin: ["bareruby_binding_onboard_led_pin.cpp", PIN],
      wireless: ["bareruby_binding_onboard_led_wireless.cpp", WIRELESS]
    }.freeze

    # Reaching the wireless LED means bringing the radio up, which is a driver and a
    # firmware blob rather than a register write, so the implementation that does it
    # names what it needs linked.
    WIRELESS_LIBRARY = "pico_cyw43_arch_none"

    def self.files(led) = { file_name(led) => IMPLEMENTATIONS.fetch(led)[1] }

    def self.file_name(led) = IMPLEMENTATIONS.fetch(led)[0]
  end
end
