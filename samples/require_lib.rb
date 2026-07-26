require_relative "require_helper"

class Counter
  include Steppable

  def initialize
    @value = 0
  end

  def bump
    @value = @value + step
    @value
  end
end
