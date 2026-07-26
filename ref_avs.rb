class PeakMeter
  def initialize(adc_pin, led_pin, led_frequency, full_swing)
    @adc = ADC.new(adc_pin)
    @led = PWM.new(led_pin, frequency: led_frequency, duty: 0)
    @full_swing = full_swing
    @lows = Array.new(6, 0)
    @highs = Array.new(6, 0)
    @at = 0
    @filled = 0
    start_frame
  end

  def measure
    value = @adc.read_raw
    @low = value if value < @low
    @high = value if value > @high
    return
  end

  def refresh
    close_frame
    percent = span * 100 / @full_swing
    percent = 100 if percent > 100
    @led.duty(percent)
    return
  end

  def close_frame
    @lows[@at] = @low
    @highs[@at] = @high
    @at = @at + 1
    @at = 0 if @at >= @lows.size
    @filled = @filled + 1 if @filled < @lows.size
    start_frame
    return
  end

  def start_frame
    @low = 4095
    @high = 0
    return
  end

  def span
    low = @lows[0]
    high = @highs[0]
    k = 1
    while k < @filled
      low = @lows[k] if @lows[k] < low
      high = @highs[k] if @highs[k] > high
      k = k + 1
    end
    return high - low
  end
end

class Heartbeat
  def initialize(pin, ticks_per_beat)
    @led = GPIO.new(pin, GPIO::OUT)
    @ticks_per_beat = ticks_per_beat
    @at = 0
  end

  def tick
    if @at < @ticks_per_beat / 2
      @led.write(1)
    else
      @led.write(0)
    end
    @at = @at + 1
    @at = 0 if @at >= @ticks_per_beat
    return
  end
end

sample_period_us = 25
frame_samples = 200
led_frequency = 5000
full_swing = 4095

meter26 = PeakMeter.new(26, 6, led_frequency, full_swing)
meter27 = PeakMeter.new(27, 7, led_frequency, full_swing)
meter28 = PeakMeter.new(28, 8, led_frequency, full_swing)

heartbeat = Heartbeat.new(25, 1000000 / sample_period_us)

taken = 0

loop do
  meter26.measure
  meter27.measure
  meter28.measure

  taken = taken + 1
  if taken >= frame_samples
    taken = 0
    meter26.refresh
    meter27.refresh
    meter28.refresh
  end

  heartbeat.tick

  asleep_us(sample_period_us)
end
