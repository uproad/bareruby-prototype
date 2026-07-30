# frozen_string_literal: true

module BareRubyProt
  # What a region is made of once the types are gone: a buffer reserved while compiling and
  # a guard that both takes it and gives it back. The guard is the whole of a block — which
  # role it plays is settled on the way in, because a block written inside a method is
  # outermost or nested depending on who calls that method. Its destructor runs on the way
  # out, which is what makes an exception leaving the block release the region as well.
  #
  # Each block is numbered so its buffer has a name of its own, and a program that writes
  # several never shares one.
  class ArenaStorage
    GUARD_STRUCT = :bareruby_arena_block
    NEW_FUNCTION = :bareruby_arena_array_new
    EXTEND_FUNCTION = :bareruby_arena_array_extend
    DUP_FUNCTION = :bareruby_arena_array_dup
    CURRENT = :bareruby_current_arena

    def initialize(low_ir, function_scope, value_layout)
      @lir = low_ir
      @function_scope = function_scope
      @value_layout = value_layout
    end

    # A block, opened: the buffer its own site reserves and the guard that decides what to
    # do with it. The size is passed along even when the block turns out to be nested,
    # where it becomes the amount the block is asking the region it landed in for.
    def opened(size)
      index = @function_scope.next_arena
      storage = :"arena_storage_#{index}"
      guard = @lir.create_declare(
        :"arena_block_#{index}", @lir.struct_type(GUARD_STRUCT),
        @lir.create_call(
          GUARD_STRUCT,
          [@lir.create_local(storage, @lir.pointer_type(:uint8)), @lir.create_const_int(size, :int32)],
          @lir.struct_type(GUARD_STRUCT)
        )
      )
      [@lir.create_declare_arena_storage(storage, size), guard]
    end

    # Whichever region is current. A binding that needs somewhere to put what it receives
    # names this rather than a local, because the program writes none.
    def current = @lir.create_local(CURRENT, @lir.pointer_type(@lir.struct_type(:bareruby_arena_t)))

    def allocation(length, element)
      @lir.create_call(NEW_FUNCTION, [length, @value_layout.element_size(element)], handle_type)
    end

    # Making room and reading back where the elements now are: growing moves them, so the
    # pointer the write uses has to be the one that comes back rather than one read before.
    def extension(receiver, length, element)
      @lir.create_cast(
        @lir.create_call(
          EXTEND_FUNCTION, [receiver, length, @value_layout.element_size(element)],
          @lir.pointer_type(:void)
        ),
        @lir.pointer_type(element)
      )
    end

    def duplication(receiver, element)
      @lir.create_call(DUP_FUNCTION, [receiver, @value_layout.element_size(element)], handle_type)
    end

    private

    def handle_type = @lir.pointer_type(@lir.struct_type(ValueLayout::ARRAY_STRUCT))
  end
end
