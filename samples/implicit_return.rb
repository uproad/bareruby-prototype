class Counter
  def initialize(start)
    @value = start
    announce
  end

  def announce
    puts @value
  end

  def bump
    @value = @value + 1
    return
  end

  def value
    @value
  end

  def bump_by(times)
    i = 0
    while i < times
      bump
      i = i + 1
    end
  end

  def bump_once_or_twice(twice)
    if twice
      bump
      bump
    else
      bump
    end
  end
end

counter = Counter.new(10)
puts counter.value

counter.bump_by(3)
puts counter.value

counter.bump_once_or_twice(true)
puts counter.value

counter.bump_once_or_twice(false)
puts counter.value

counter.announce
