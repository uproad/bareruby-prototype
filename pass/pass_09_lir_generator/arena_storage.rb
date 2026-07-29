# frozen_string_literal: true

module BareRubyProt
  # What a region is made of once the types are gone: a buffer reserved while compiling, a
  # handle pointing at it, and — for a block's region — a guard whose destructor puts the
  # pointer back on the way out, which is what makes an exception leaving the block
  # release the region as well. Allocation is that pointer moving forward.
  #
  # Each region is numbered so its buffer and its guard have names of their own, and a
  # program that declares several never shares one.
  class ArenaStorage
    STRUCT = :bareruby_arena_t
    SCOPE_STRUCT = :bareruby_arena_scope

    def initialize(low_ir, function_scope)
      @lir = low_ir
      @function_scope = function_scope
    end

    def struct_type = @lir.struct_type(STRUCT)

    # A block's region, opened: the handle, its buffer, and the guard that releases it.
    def opened(name, size)
      index = @function_scope.next_arena
      struct = struct_type
      place = @lir.create_local(name, struct)
      statements = [@lir.create_declare(name, struct, nil)] + reserved(place, size, index) +
                   [guard(place, index)]
      [statements, place]
    end

    # A region that outlives no scope takes no guard: reset is the only thing that
    # releases it.
    def reserved_for(place, size) = reserved(place, size, @function_scope.next_arena)

    # Handing out is a bump of the pointer, and what comes back is bytes until it is told
    # what it is holding.
    def allocation(arena_reference, length_local, element_type)
      bytes = @lir.create_binary("*", length_local, @lir.create_size_of(element_type, :int32), :int32)
      call = @lir.create_call(:bareruby_arena_alloc, [arena_reference, bytes], @lir.pointer_type(:void))
      @lir.create_cast(call, @lir.pointer_type(element_type))
    end

    private

    def reserved(place, size, index)
      storage = :"arena_storage_#{index}"
      initializer = @lir.create_call(
        :bareruby_arena_init,
        [@lir.reference_to(place),
         @lir.create_local(storage, @lir.pointer_type(:uint8)),
         @lir.create_const_int(size, :int32)],
        :void
      )
      [@lir.create_declare_arena_storage(storage, size), @lir.create_expression(initializer)]
    end

    def guard(place, index)
      scope_struct = @lir.struct_type(SCOPE_STRUCT)
      @lir.create_declare(
        :"arena_scope_#{index}", scope_struct,
        @lir.create_brace_init([@lir.create_address_of(place)], scope_struct)
      )
    end
  end
end
