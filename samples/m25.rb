module Greetable
  def greet
    1
  end

  def describe
    greet + 10
  end
end

class Device
  def initialize(id)
    @id = id
  end

  def id
    @id
  end

  def label
    @id * 100
  end
end

class Sensor < Device
  include Greetable

  def initialize(id, scale)
    super(id)
    @scale = scale
  end

  def label
    super + @scale
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
    value * 2
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
