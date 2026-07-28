class OptionalValue
  def initialize(enabled)
    if enabled
      @value = 12
    end
  end

  def value
    @value
  end
end

enabled = false

if enabled
  assigned_in_if = 3
end
puts(assigned_in_if.nil?)
puts(assigned_in_if || 8)

while enabled
  assigned_in_while = 4
end
puts(assigned_in_while.nil?)
puts(assigned_in_while || 9)

value_of_if = if enabled
  5
end
puts(value_of_if.nil?)
puts(value_of_if || 10)

absent = OptionalValue.new(false)
puts(absent.value.nil?)
puts(absent.value || 11)

present = OptionalValue.new(true)
puts(present.value.nil?)
puts(present.value || 11)
