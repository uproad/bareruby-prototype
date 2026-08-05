# The onboard LED: the one peripheral every board has, and the one no program has to be
# told where to find. On the machine doing the compiling there is no LED, so the calls
# land on stubs that say so on fd2 — which is what lets this program run before any board
# has been attached.
led = OnboardLED.new

loop do
  led.on
  sleep_ms(500)
  led.off
  sleep_ms(500)
end
