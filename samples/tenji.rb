class Window
  def initialize
    @samples = Array.new(20, 0.0)
    @at = 0
  end

  def push(value)
    @samples[@at] = value
    @at = @at + 1
    @at = 0 if @at >= @samples.size
  end

  def span
    low = @samples[0]
    high = @samples[0]
    k = 1
    while k < @samples.size
      low = @samples[k] if @samples[k] < low
      high = @samples[k] if @samples[k] > high
      k = k + 1
    end
    high - low
  end
end

loop_sleep_ms = 10

wd_res = 1000 / loop_sleep_ms
wd_i = 0

m = 20

w26 = Window.new
w27 = Window.new
w28 = Window.new

l = GPIO.new(25, GPIO::OUT)

f = 100000
duty = 10000

p6 = PWM.new(6, frequency: f, duty: duty)
p7 = PWM.new(7, frequency: f, duty: duty)
p8 = PWM.new(8, frequency: f, duty: duty)

p6.duty(0)
p7.duty(0)
p8.duty(0)

m26 = 0.1
m27 = 0.1
m28 = 0.1

b26 = 3.3
b27 = 3.3
b28 = 3.3

a26 = ADC.new(26)
a27 = ADC.new(27)
a28 = ADC.new(28)

i = 0

loop do
  w26.push(a26.read)
  w27.push(a27.read)
  w28.push(a28.read)

  x26 = w26.span / 3.3
  x27 = w27.span / 3.3
  x28 = w28.span / 3.3

  m26 = x26 if m26 < x26
  m27 = x27 if m27 < x27
  m28 = x28 if m28 < x28

  b26 = x26 if b26 > x26
  b27 = x27 if b27 > x27
  b28 = x28 if b28 > x28

  x26 = (x26 - b26) / m26
  x27 = (x27 - b27) / m27
  x28 = (x28 - b28) / m28

  duty26 = x26
  duty26 = 0.0 if duty26 < 0.0
  duty26 = 1.0 if duty26 > 1.0

  duty27 = x27
  duty27 = 0.0 if duty27 < 0.0
  duty27 = 1.0 if duty27 > 1.0

  duty28 = x28
  duty28 = 0.0 if duty28 < 0.0
  duty28 = 1.0 if duty28 > 1.0

  duty26 = duty26 * 120 - 10
  duty27 = duty27 * 120 - 10
  duty28 = duty28 * 120 - 10

  duty26 = 0.0 if duty26 < 0.0
  duty26 = 100.0 if duty26 > 100.0

  duty27 = 0.0 if duty27 < 0.0
  duty27 = 100.0 if duty27 > 100.0

  duty28 = 0.0 if duty28 < 0.0
  duty28 = 100.0 if duty28 > 100.0

  p6.duty(duty26.to_i32)
  p7.duty(duty27.to_i32)
  p8.duty(duty28.to_i32)

  i = i + 1

  if i >= m
    i = 0

    m26 = m26 - 0.1 if m26 > 0.5
    m27 = m27 - 0.1 if m27 > 0.5
    m28 = m28 - 0.1 if m28 > 0.5
  end

  if wd_i < wd_res / 2
    l.write(1)
  else
    l.write(0)
  end

  wd_i = wd_i + 1
  wd_i = 0 if wd_i >= wd_res

  sleep_ms(loop_sleep_ms)
end
