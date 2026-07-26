class Classifier
  def initialize
    @calls = 0
  end

  def classify(value)
    @calls = @calls + 1
    if value < 0
      0
    elsif value == 0
      1
    else
      2
    end
  end

  def calls
    @calls
  end
end

classifier = Classifier.new

total = 0
index = 0
while index < 10
  if index % 2 == 0 && index > 2
    total = total + index
  end
  index = index + 1
end
puts total

puts classifier.classify(-5)
puts classifier.classify(0)
puts classifier.classify(7)
puts classifier.calls

flag = total > 20
picked = if flag
  100
else
  200
end
puts picked

unless flag
  puts 1
else
  puts 2
end

class Reporter
  def initialize(label)
    @label = label
    @count = 0
  end

  def bump(amount)
    @count = @count + amount
    @count
  end

  def report
    puts "#{@label}: count=#{@count} (100% done)"
  end
end

reporter = Reporter.new("sensor")
puts "starting"
reporter.bump(3)
reporter.bump(4)
reporter.report

value = 42
name = "pin"
puts "#{name} = #{value}"
puts "plain literal"
big = 3000000000
puts "big=#{big} small=#{value}"

class Machine2
  def initialize
    @state = :idle
  end

  def start
    @state = :running
  end

  def running?
    @state == :running
  end

  def state
    @state
  end
end

machine = Machine2.new
puts "idle? #{machine.running?}"
machine.start
puts "running? #{machine.running?}"

mode = :verbose
if mode == :verbose
  puts "verbose mode"
end
if mode == :quiet
  puts "quiet mode"
end
