class Window
  def initialize
    @samples = Array.new(4, 0)
    @at = 0
  end

  def push(value)
    @samples[@at] = value
    @at = @at + 1
    @at = 0 if @at >= @samples.size
  end

  def peak
    best = @samples[0]
    k = 1
    while k < @samples.size
      best = @samples[k] if @samples[k] > best
      k = k + 1
    end
    best
  end
end

window = Window.new
window.push(3)
window.push(9)
window.push(4)
puts window.peak

size = 5
squares = Array.new(size, 0)
i = 0
while i < size
  squares[i] = i * i
  i = i + 1
end
puts squares[4]
puts squares.size

names = [1, 2, 3]
puts names[1]

ratios = Array.new(3, 0.5)
ratios[1] = 1.25
puts ratios[0]
puts ratios[1]

shared = squares
shared[0] = 100
puts squares[0]

copied = squares.dup
copied[1] = 200
puts squares[1]
puts copied[1]

blank = Array.new(2)
blank[0] = 8
blank[1] = 9
puts blank[0] + blank[1]
