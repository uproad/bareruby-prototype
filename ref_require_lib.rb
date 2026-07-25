require_relative "ref_require_helper"

class Counter
  include Steppable

  def initialize
    @value = 0
  end

  def bump
    @value = @value + step
    return @value
  end
end
