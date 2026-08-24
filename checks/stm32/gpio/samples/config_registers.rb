# Five configurations on port C, whose reset values are all zero: direction into MODER,
# the pulls into PUPDR, and HIGH_Z landing as input with no pull — the registers are
# read by the harness after the program stops. The open-drain pin exercises its init
# path, but its register is not read: Renode 1.16.1's STM32_GPIOPort drops OTYPER
# writes (a tagged, unimplemented register), so that reflection stays on hardware.
out_pin = GPIO.new(32, GPIO::OUT)
od_pin = GPIO.new(33, GPIO::OUT | GPIO::OPEN_DRAIN)
up_pin = GPIO.new(34, GPIO::IN | GPIO::PULL_UP)
down_pin = GPIO.new(35, GPIO::IN | GPIO::PULL_DOWN)
z_pin = GPIO.new(36, GPIO::HIGH_Z)
puts "configured"
