class PeakToPeakDetector
  def initialize(adc_pin)
    @adc = ADC.new(adc_pin)
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

  def advance
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

class Led
  def initialize(pin, frequency)
    @pwm = PWM.new(pin, frequency: frequency, duty: 0)
  end

  def brightness=(percent)
    @pwm.duty(percent)
    return
  end
end

class AudioVisualizer
  def initialize(detector, led, full_swing)
    @detector = detector
    @led = led
    @full_swing = full_swing
  end

  def measure
    @detector.measure
    return
  end

  def refresh
    @detector.advance
    percent = @detector.span * 100 / @full_swing
    percent = 100 if percent > 100
    @led.brightness = percent
    return
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

visualizer26 = AudioVisualizer.new(PeakToPeakDetector.new(26), Led.new(6, led_frequency), full_swing)
visualizer27 = AudioVisualizer.new(PeakToPeakDetector.new(27), Led.new(7, led_frequency), full_swing)
visualizer28 = AudioVisualizer.new(PeakToPeakDetector.new(28), Led.new(8, led_frequency), full_swing)

heartbeat = Heartbeat.new(25, 1000000 / sample_period_us)

taken = 0

loop do
  visualizer26.measure
  visualizer27.measure
  visualizer28.measure

  taken = taken + 1
  if taken >= frame_samples
    taken = 0
    visualizer26.refresh
    visualizer27.refresh
    visualizer28.refresh
  end

  heartbeat.tick

  asleep_us(sample_period_us)
end
