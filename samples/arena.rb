class Tokenizer
  def initialize
    @scanned = 0
  end

  def scan(length)
    values = Arena::Array.new(length)
    i = 0
    while i < length
      values[i] = i * i
      i = i + 1
    end
    @scanned = @scanned + 1
    values
  end

  def widest(values)
    best = values[0]
    i = 1
    while i < values.size
      best = values[i] if values[i] > best
      i = i + 1
    end
    best
  end

  def scanned
    @scanned
  end

  def report(values)
    line = Arena::String.new("size=#{values.size}")
    line << " scanned"
    line
  end
end

tokenizer = Tokenizer.new

arena(4096) do
  grown = []
  grown[20] = 7
  puts grown.size
  puts grown[5]
  grown << 99
  puts grown.size

  width = 3
  height = 2
  values = tokenizer.scan(width * height)
  puts values.size
  puts tokenizer.widest(values)

  filled = Arena::Array.new(4, 0)
  filled[1] = 9
  puts filled[1]

  shared = values
  shared[0] = 100
  puts tokenizer.widest(shared)

  k = 0
  while k < 1000
    arena do
      scratch = Arena::Array.new(8, 0)
      scratch[0] = k
    end
    k = k + 1
  end

  puts tokenizer.widest(values)

  note = ""
  note << "count="
  note << "#{tokenizer.scanned}"
  puts note

  puts tokenizer.report(values)

  fixed = ::Array.new(3, 0)
  fixed[2] = 5
  puts fixed[2]
end

begin
  arena(64) do
    values = []
    values[0] = 1
    raise "leaving early"
  end
rescue
  puts "released"
end

arena(4096) do
  values = tokenizer.scan(4)
  puts tokenizer.widest(values)
end

arena(8192) do
  arena(4096) do
    a = Arena::Array.new(1024, 0)
    puts a.size
  end
end
