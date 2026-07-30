class Report
  def entry(label, value)
    text = Arena::String.new(label)
    text << ": "
    text << "#{value}"
    text
  end

  def summary(count)
    text = Arena::String.new("readings")
    i = 0
    while i < count
      text << ", #{i * i}"
      i = i + 1
    end
    text
  end

  def kept(count)
    summary(count)
  end
end

report = Report.new

arena(1024) do
  temperature = report.entry("temperature", 21)
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

  message = Arena::String.new("count: #{3 * 4}")
  puts message
  puts message.length

  arena(256) do
    inner = Arena::String.new("inner")
    inner << " string"
    puts inner
    carried = Arena::String.new(inner)
    puts carried
  end

  grown = ""
  i = 0
  while i < 8
    grown << "0123456789"
    i = i + 1
  end
  puts grown.size
end

arena(512) do
  puts report.kept(4)
end

arena(512) do
  puts report.kept(6)
end
