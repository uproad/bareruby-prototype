# frozen_string_literal: true

module BareRubyProt
  # What lowering one function has to remember: which locals it has already declared,
  # which of those hold a pointer rather than a value, and the numbering behind the names
  # it invents. A nested body declares into the same function but its declarations end
  # with it, which is what the C++ scope it becomes does too.
  class FunctionScope
    attr_reader :self_type, :return_type

    def initialize(self_type:, return_type:, void_return:)
      @self_type = self_type
      @return_type = return_type
      @void_return = void_return
      @declared = []
      @pointers = []
      @temporaries = 0
      @arenas = 0
    end

    def void_return? = @void_return

    def declared?(name) = @declared.include?(name)

    def declare(name) = @declared << name

    def pointer?(name) = @pointers.include?(name)

    def declare_pointer(name) = @pointers << name

    def next_temporary
      @temporaries += 1
      :"temporary_#{@temporaries}"
    end

    def next_arena = @arenas += 1

    def nested
      declared = @declared.dup
      pointers = @pointers.dup
      yield
    ensure
      @declared = declared
      @pointers = pointers
    end
  end
end
