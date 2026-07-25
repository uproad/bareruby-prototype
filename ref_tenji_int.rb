class Window
  def initialize
    @samples = Array.new(20, 0)
    @at = 0
  end

  def push(value)
    @samples[@at] = value
    @at = @at + 1
    @at = 0 if @at >= @samples.size
    return
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
    return high - low
  end
end

loop_sleep_ms = 10

wd_res = 1000 / loop_sleep_ms
wd_i = 0

m = 20

one = 4096

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

m26 = 410
m27 = 410
m28 = 410

b26 = 13517
b27 = 13517
b28 = 13517

a26 = ADC.new(26)
a27 = ADC.new(27)
a28 = ADC.new(28)

i = 0

loop do
  w26.push(a26.read_raw)
  w27.push(a27.read_raw)
  w28.push(a28.read_raw)

  x26 = w26.span
  x27 = w27.span
  x28 = w28.span

  m26 = x26 if m26 < x26
  m27 = x27 if m27 < x27
  m28 = x28 if m28 < x28

  b26 = x26 if b26 > x26
  b27 = x27 if b27 > x27
  b28 = x28 if b28 > x28

  x26 = (x26 - b26) * one / m26
  x27 = (x27 - b27) * one / m27
  x28 = (x28 - b28) * one / m28

  duty26 = x26
  duty26 = 0 if duty26 < 0
  duty26 = one if duty26 > one

  duty27 = x27
  duty27 = 0 if duty27 < 0
  duty27 = one if duty27 > one

  duty28 = x28
  duty28 = 0 if duty28 < 0
  duty28 = one if duty28 > one

  duty26 = duty26 * 120 / one - 10
  duty27 = duty27 * 120 / one - 10
  duty28 = duty28 * 120 / one - 10

  duty26 = 0 if duty26 < 0
  duty26 = 100 if duty26 > 100

  duty27 = 0 if duty27 < 0
  duty27 = 100 if duty27 > 100

  duty28 = 0 if duty28 < 0
  duty28 = 100 if duty28 > 100

  p6.duty(duty26)
  p7.duty(duty27)
  p8.duty(duty28)

  i = i + 1

  if i >= m
    i = 0

    m26 = m26 - 410 if m26 > 2048
    m27 = m27 - 410 if m27 > 2048
    m28 = m28 - 410 if m28 > 2048
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
