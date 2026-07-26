class PeakToPeakDetector
  def initialize(adc_pin, full_scale)
    @adc = ADC.new(adc_pin)
    @full_scale = full_scale
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
    @low = @full_scale
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

class AudioVisualizer
  def initialize(gate, swing_floor, swing_decay)
    @gate = gate
    @swing_floor = swing_floor
    @swing_decay = swing_decay
    @swing = gate
    @span = 0
  end

  def observe(span)
    @swing = @swing - @swing_decay if @swing > @swing_floor
    @swing = span if span > @swing
    @span = span
    return
  end

  def brightness_percent
    return 0 if @span < @gate
    return @span * 100 / @swing
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
full_scale = 4095
gate = 40
swing_floor = 410
decay_seconds = 10

frames_per_second = 1000000 / (sample_period_us * frame_samples)
decay_frames = decay_seconds * frames_per_second
swing_decay = (full_scale - swing_floor + decay_frames / 2) / decay_frames

detector26 = PeakToPeakDetector.new(26, full_scale)
detector27 = PeakToPeakDetector.new(27, full_scale)
detector28 = PeakToPeakDetector.new(28, full_scale)

visualizer26 = AudioVisualizer.new(gate, swing_floor, swing_decay)
visualizer27 = AudioVisualizer.new(gate, swing_floor, swing_decay)
visualizer28 = AudioVisualizer.new(gate, swing_floor, swing_decay)

led6 = Led.new(6, led_frequency)
led7 = Led.new(7, led_frequency)
led8 = Led.new(8, led_frequency)

heartbeat = Heartbeat.new(25, 1000000 / sample_period_us)

taken = 0

loop do
  detector26.measure
  detector27.measure
  detector28.measure

  taken = taken + 1
  if taken >= frame_samples
    taken = 0

    detector26.advance
    visualizer26.observe(detector26.span)
    led6.brightness = visualizer26.brightness_percent

    detector27.advance
    visualizer27.observe(detector27.span)
    led7.brightness = visualizer27.brightness_percent

    detector28.advance
    visualizer28.observe(detector28.span)
    led8.brightness = visualizer28.brightness_percent
  end

  heartbeat.tick

  asleep_us(sample_period_us)
end
