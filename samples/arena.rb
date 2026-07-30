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
  puts grown.size                    # => 21, the write past the end grew it
  puts grown[5]                      # => 0, an element never written reads the default
  grown << 99
  puts grown.size                    # => 22

  width = 3
  height = 2
  values = tokenizer.scan(width * height)
  puts values.size                   # => 6
  puts tokenizer.widest(values)      # => 25

  filled = Arena::Array.new(4, 0)
  filled[1] = 9
  puts filled[1]                     # => 9

  shared = values
  shared[0] = 100
  puts tokenizer.widest(shared)      # => 100, shared names the same array as values

  k = 0
  while k < 1000
    arena do
      scratch = Arena::Array.new(8, 0)
      scratch[0] = k
    end
    k = k + 1
  end

  puts tokenizer.widest(values)      # => 100, a thousand release points left it alone

  note = ""
  note << "count="
  note << "#{tokenizer.scanned}"
  puts note                          # => count=1

  puts tokenizer.report(values)      # => size=6 scanned

  fixed = ::Array.new(3, 0)
  fixed[2] = 5
  puts fixed[2]                      # => 5
end

begin
  arena(64) do
    values = []
    values[0] = 1
    raise "leaving early"
  end
rescue
  puts "released"                    # => released, the region went back on the way out
end

# Running out of a region is thrown rather than stopped on, so a program can answer it and
# carry on. There are three ways to reach it and all three land here.
begin
  arena(64) do
    values = Arena::Array.new(1000, 0)
    puts values.size
  end
rescue
  puts "asked for more than the region holds"   # => asked for more than the region holds
end

begin
  arena(64) do
    arena(4096) do                   # the inner block declares what it needs, and asking
      puts 1                         # on the way in says so before anything is allocated
    end
  end
rescue
  puts "nested block wanted more than was left" # => nested block wanted more than was left
end

begin
  arena(64) do
    grown = []
    i = 0
    while i < 100
      grown << i                     # growing takes a bigger block each time it doubles
      i = i + 1
    end
    puts grown.size
  end
rescue
  puts "grew past the end of the region"        # => grew past the end of the region
end

arena(4096) do
  values = tokenizer.scan(4)
  puts tokenizer.widest(values)      # => 9, this block starts where the first one did
end

arena(8192) do
  arena(4096) do
    a = Arena::Array.new(1024, 0)
    puts a.size                      # => 1024, the inner block asks the outer region for room
  end
end
