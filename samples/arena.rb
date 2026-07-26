class Series
  def initialize
    @pool = Arena.new(size: 64)
  end

  def squares(a, count)
    values = a.array(count)
    i = 0
    while i < count
      values[i] = i * i
      i = i + 1
    end
    values
  end

  def largest(values)
    best = values[0]
    i = 1
    while i < values.size
      best = values[i] if values[i] > best
      i = i + 1
    end
    best
  end

  def kept(count)
    @pool.reset
    squares(@pool, count)
  end
end

width = 3
height = 2
series = Series.new

arena(size: 256) do |a|
  values = series.squares(a, width * height)
  puts values.size
  puts series.largest(values)

  shared = values
  shared[0] = 100
  puts series.largest(shared)

  arena(size: 64) do |b|
    doubles = b.array(3)
    doubles[0] = values[2] * 2
    doubles[1] = values[3] * 2
    doubles[2] = values[4] * 2
    puts series.largest(doubles)
  end

  ratios = a.array(2)
  ratios[0] = 0.5
  ratios[1] = ratios[0] * 3
  puts ratios[1]
end

begin
  arena(size: 64) do |a|
    values = a.array(2)
    values[0] = 1
    raise "leaving early"
  end
rescue
  puts "released"
end

puts series.largest(series.kept(4))
puts series.largest(series.kept(7))
