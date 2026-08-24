# One conversion on PA4 (ADC1_IN4), then stop. The harness reads back what the
# initialization and the read left behind: the channel in SQR3's first rank, its
# sample time in SMPR2, CR2 with the conversion settings and ADON down again, and
# the prescaler in the common CCR.
adc = ADC.new(4)
puts "raw #{adc.read_raw}"
