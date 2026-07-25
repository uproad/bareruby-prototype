module Greetable
  def greet
    return 1
  end

  def describe
    return greet + 10
  end
end

class Device
  def initialize(id)
    @id = id
  end

  def id
    return @id
  end

  def label
    return @id * 100
  end
end

class Sensor < Device
  include Greetable

  def initialize(id, scale)
    super(id)
    @scale = scale
  end

  def label
    return super + @scale
  end
end

device = Device.new(3)
puts device.label

sensor = Sensor.new(3, 7)
puts sensor.id
puts sensor.label
puts sensor.greet
puts sensor.describe

class Guard
  def check(value)
    if value < 0
      raise "negative value"
    end
    return value * 2
  end
end

guard = Guard.new
puts guard.check(5)

begin
  puts guard.check(-1)
  puts "not reached"
rescue
  puts "rescued"
end

puts "after"

count = 7
ratio = 0.25
ready = true

line = "count=#{count} ratio=#{ratio} ready=#{ready}"
puts line

label = "id"
message = "#{label}: #{count * 3}"
puts message
puts "direct: #{count}"
