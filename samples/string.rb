class Report
  def initialize
    @scratch = Arena.new(size: 512)
  end

  def entry(a, label, value)
    text = a.string(label)
    text << ": "
    text << "#{value}"
    text
  end

  def summary(a, count)
    text = a.string("readings")
    i = 0
    while i < count
      text << ", #{i * i}"
      i = i + 1
    end
    text
  end

  def kept(count)
    @scratch.reset
    summary(@scratch, count)
  end
end

report = Report.new

arena(size: 1024) do |a|
  temperature = report.entry(a, "temperature", 21)
  puts temperature
  puts temperature.size

  same = temperature
  same << " C"
  puts temperature

  reported = temperature + " (reported)"
  puts reported
  puts temperature
  puts reported == "temperature: 21 C (reported)"
  puts reported != temperature.dup

  message = a.string("count: #{3 * 4}")
  puts message
  puts message.length

  arena(size: 256) do |b|
    inner = b.string("inner")
    inner << " string"
    puts inner
    carried = a.string(inner)
    puts carried
  end

  grown = a.string("")
  i = 0
  while i < 8
    grown << "0123456789"
    i = i + 1
  end
  puts grown.size
end

puts report.kept(4)
puts report.kept(6)
