class Lamp
  def initialize(at)
    @at = at
    @level = 0
  end

  def at
    @at
  end

  def level
    @level
  end

  def set(level)
    @level = level
  end
end

class Bank
  def initialize(count)
    @lamps = Array.new(4)
    i = 0
    while i < count
      @lamps[i] = Lamp.new(i * 10)
      i = i + 1
    end
    @count = count
  end

  def light(level)
    i = 0
    while i < @count
      @lamps[i].set(level)
      i = i + 1
    end
  end

  def level_at(i)
    @lamps[i].level
  end

  def lamp_at(i)
    @lamps[i]
  end
end

class Brightener
  def brighten(lamp)
    lamp.set(lamp.level + 1)
  end
end

lamps = Array.new(4)
i = 0
while i < 4
  lamps[i] = Lamp.new(i * 10)
  i = i + 1
end

puts lamps[2].at
puts lamps[2].level

lamps[2].set(7)
puts lamps[2].level

taken = lamps[2]
taken.set(9)
puts lamps[2].level

Brightener.new.brighten(lamps[2])
puts lamps[2].level

bank = Bank.new(3)
bank.light(5)
puts bank.level_at(0)
puts bank.level_at(2)

bank.lamp_at(1).set(6)
puts bank.level_at(1)

spare = Lamp.new(99)
pair = Array.new(2)
pair[0] = spare
pair[1] = lamps[3]

spare.set(3)
puts pair[0].level

lamps[3].set(4)
puts pair[1].level

mirror = Array.new(4)
i = 0
while i < 4
  mirror[i] = lamps[i]
  i = i + 1
end

lamps[0].set(8)
puts mirror[0].level

shared = Lamp.new(50)
three = Array.new(3, shared)
three[0].set(51)
puts three[2].level
puts shared.level

pins = Array.new(3)
i = 0
while i < 3
  pins[i] = GPIO.new(i + 14, GPIO::OUT)
  i = i + 1
end

i = 0
while i < 3
  pins[i].write(1)
  i = i + 1
end

puts pins[1].read
