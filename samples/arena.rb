width = 3
height = 2
count = width * height

arena(size: 256) do |a|
  squares = a.array(count)
  i = 0
  while i < squares.size
    squares[i] = i * i
    i = i + 1
  end
  puts squares.size
  puts squares[5]

  shared = squares
  shared[0] = 100
  puts squares[0]

  arena(size: 64) do |b|
    doubles = b.array(3)
    doubles[0] = squares[2] * 2
    doubles[1] = squares[3] * 2
    doubles[2] = squares[4] * 2
    puts doubles[2]
  end
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

pool = Arena.new(size: 128)
first = pool.array(4)
first[0] = 7
puts first[0]
pool.reset
second = pool.array(4)
second[0] = 11
puts second[0]

arena(size: 64) do |a|
  ratios = a.array(2)
  ratios[0] = 0.5
  ratios[1] = ratios[0] * 3
  puts ratios[1]
end
