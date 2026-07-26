class Counter
  def initialize(start)
    @value = start
  end

  def bump
    @value = @value + 1
    return
  end

  def value
    return @value
  end
end

class Loader
  def load(counter, times)
    i = 0
    while i < times
      counter.bump
      i = i + 1
    end
    return
  end
end

class Tally
  def initialize(counter)
    @counter = counter
    @calls = 0
  end

  def record
    @counter.bump
    @calls = @calls + 1
    return
  end

  def counter
    return @counter
  end

  def calls
    return @calls
  end
end

class Pair
  def initialize
    @left = Counter.new(0)
    @right = Counter.new(10)
  end

  def left
    return @left
  end

  def right
    return @right
  end

  def bump_both
    @left.bump
    @right.bump
    return
  end
end

counter = Counter.new(0)

Loader.new.load(counter, 3)
puts counter.value

same = counter
same.bump
puts counter.value

tally = Tally.new(counter)
tally.record
tally.record
puts counter.value
puts tally.calls

taken = tally.counter
taken.bump
puts counter.value

pair = Pair.new
pair.bump_both
puts pair.left.value
puts pair.right.value

pair.left.bump
puts pair.left.value
