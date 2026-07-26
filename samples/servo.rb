class Servo
  def initialize(pin)
    @pwm = PWM.new(pin, frequency: 50)
    @angle = 0
  end

  def move(angle)
    @angle = angle
    @pwm.pulse_width_us(1000 + (angle * 1000 / 180))
    return
  end

  def angle
    return @angle
  end
end

servo = Servo.new(15)

loop do
  0.upto(180) do |angle|
    servo.move(angle)
    Machine.delay_us(500)
  end
  sleep_ms(300)
end
