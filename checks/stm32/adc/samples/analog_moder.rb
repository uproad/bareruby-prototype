# Port C's reset MODER is all zero, so PC0 (pin 32, ADC1_IN10) initialized for the
# ADC is the one field written: analog mode, MODER bits 11. The harness reads the
# register back after the program stops — Renode's STM32_GPIOPort holds MODER, so
# this reflection needs no model of the converter at all.
adc = ADC.new(32)
puts "configured"
