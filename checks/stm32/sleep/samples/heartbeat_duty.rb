# samples/heartbeat.rb's shape: 100ms on, 900ms off. The hand-run record in
# checks/emulate.yml held 0.1 ± 0.05; here the emulator's virtual time pins it.
led = OnboardLED.new
puts "beating"
loop do
  led.on
  sleep_ms(100)
  led.off
  sleep_ms(900)
end
