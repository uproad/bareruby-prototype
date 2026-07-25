class Counter
  def initialize(initial)
    @value = initial
  end

  def reset
    @value = 0
    return
  end

  def advance(step, limit)
    mask = (1 << 3) - 1
    adjustment = -step
    adjustment += 1
    @value += adjustment

    limit.times do |index|
      @value = @value + index
      next
    end

    1.upto(limit) do |index|
      @value = @value << 1
    end

    loop do
      break
    end

    @value = @value & mask
    return @value
  end
end

counter = Counter.new(0)
counter.reset
result = counter.advance(1, 2)
puts result
