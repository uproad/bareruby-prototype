class Source
  def maybe_number(enabled)
    if enabled
      41
    else
      nil
    end
  end

  def maybe_message(a, enabled)
    if enabled
      a.string("ready")
    end
  end
end

source = Source.new

missing = source.maybe_number(false)
puts(missing.nil?)
puts(missing || 5)

present = source.maybe_number(true)
if present
  puts(present + 1)
end

loop_enabled = true
while loop_value = source.maybe_number(loop_enabled)
  puts(loop_value)
  loop_enabled = false
end

enabled = false
if enabled
  assigned_on_one_path = 9
end
puts(assigned_on_one_path || 7)

arena(size: 128) do |a|
  message = source.maybe_message(a, true)
  if message
    puts(message)
  end
  puts(message&.size || 0)
end
