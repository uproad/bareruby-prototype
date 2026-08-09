# frozen_string_literal: true

module BareRubyProt
  # How a BareRuby value is represented once the types are gone: which low-level type it
  # becomes, which struct has to be declared for it, and where the parts of that struct
  # are reached. A struct is declared once however many times the type appears, so this
  # holds the ones it has already answered for and hands out the same one again.
  class ValueLayout
    STRING_STRUCT = :bareruby_string_t
    STRING_VIEW_STRUCT = :bareruby_string_view_t
    ARRAY_STRUCT = :bareruby_arena_array_t

    def initialize(low_ir)
      @lir = low_ir
      @array_structs = {}
      @nilable_structs = {}
    end

    def structs = @nilable_structs.values + @array_structs.values

    def type_of(type)
      case type
      when :Int8, :Int16, :Int32 then :int32
      when :Int64 then :int64
      when :Bool then :bool
      when :Fixed then :fixed
      when :String then :string_ptr
      when Hash then struct_type_of(type)
      else :void
      end
    end

    # A shared value in value position is always a reference: returning one by value
    # would copy it, and nothing but dup copies an object.
    def value_type_of(type) = shared?(type) ? @lir.pointer_type(type_of(type)) : type_of(type)

    def instance?(type) = type.is_a?(Hash) && type[:kind] == :instance

    def array?(type) = type.is_a?(Hash) && type[:kind] == :array

    def shared?(type) = instance?(type) || array?(type)

    def nilable?(type) = type.is_a?(Hash) && type[:kind] == :nilable

    def arena_string?(type) = type.is_a?(Hash) && type[:kind] == :arena_string

    def arena_array?(type) = type.is_a?(Hash) && type[:kind] == :arena_array

    # What a fixed-capacity array holds and how much of it. An arena array knows its
    # element the same way but carries its length at run time, so it has no capacity to
    # answer for.
    def element_of(type) = type[:element]

    def capacity_of(type) = type[:capacity]

    # A variable-length string is always the pointer the region handed out, never a
    # struct of its own: the handle lives in the region with the bytes, so a binding
    # holds the address of the one string rather than a copy of a handle whose length
    # the next append would leave behind. The runtime declares the struct, and nothing
    # here reads a field of it.
    def arena_string_type = @lir.pointer_type(@lir.struct_type(STRING_STRUCT))

    # A view is the pointer a binding handed a handler, never a copy: the bytes it names
    # stay the binding's, and the header declares the struct — nothing here reads a field.
    def string_view_type = @lir.pointer_type(@lir.struct_type(STRING_VIEW_STRUCT))

    def absent(type)
      @lir.create_brace_init(
        [@lir.create_const_bool(false), zero_value(value_type_of(type[:inner]))], type_of(type)
      )
    end

    def tag_of(expression) = @lir.create_field_access(expression, :tag, :bool)

    def truth_of(expression, type)
      tag = tag_of(expression)
      return tag unless type[:inner] == :Bool

      @lir.create_binary("&&", tag, value_of(expression, type), :bool)
    end

    def value_of(expression, type)
      @lir.create_field_access(expression, :value, value_type_of(type[:inner]))
    end

    def items_of(base) = @lir.create_field_access(base, :items, nil)

    def length_of(base) = @lir.create_field_access(base, :length, :int32)

    # The runtime holds the elements as bytes because it does not know what they are.
    # Indexing casts them back, which keeps a read the pointer arithmetic it was.
    def arena_items_of(base, element)
      @lir.create_cast(items_of(base), @lir.pointer_type(element))
    end

    def element_size(element) = @lir.create_size_of(element, :int32)

    def field_name(name) = name.to_s.delete_prefix("@").to_sym

    private

    def struct_type_of(type)
      case type[:kind]
      when :array then array_struct_type(type)
      when :arena_array then arena_array_type
      when :arena_string then arena_string_type
      when :string_view then string_view_type
      when :nilable then nilable_struct_type(type)
      else @lir.struct_type(type[:struct] || type[:class_name])
      end
    end

    # T? is deliberately uniform: one explicit tag followed by the ordinary value
    # representation. No pointer niche or target-specific sentinel is involved.
    def nilable_struct_type(type)
      inner = type[:inner]
      name = :"bareruby_nilable_#{nilable_type_name(inner)}_t"
      @nilable_structs[name] ||= @lir.create_struct(
        name,
        [@lir.create_field(:tag, :bool), @lir.create_field(:value, value_type_of(inner))]
      )
      @lir.struct_type(name)
    end

    def nilable_type_name(type)
      return type.to_s.downcase if type.is_a?(Symbol)
      return "arena_string" if type[:kind] == :arena_string
      return "array_#{type[:capacity]}" if type[:kind] == :array
      return type[:class_name].to_s.downcase if type[:kind] == :instance

      type[:kind].to_s
    end

    # An array becomes a struct wrapping one C array so that dup is a plain assignment
    # and an owner can embed one inline. A raw C array would decay to a pointer.
    def array_struct_type(type)
      raise "the element type of this array was never determined" if type[:element].nil?

      element = type_of(type[:element])
      name = :"bareruby_array_#{element}_#{type[:capacity]}_t"
      @array_structs[name] ||= @lir.create_struct(
        name, [@lir.create_field(:items, @lir.c_array_type(element, type[:capacity]))]
      )
      @lir.struct_type(name)
    end

    # Like the variable-length string, an arena array is always the pointer the region
    # handed out. It cannot be a handle held by value: writing past the end takes a bigger
    # block and moves both the pointer and the length, and every binding has to see that.
    # A copy of a handle would keep naming the block the array has left behind, and
    # whether an append were observed would depend on how much room happened to be left.
    def arena_array_type = @lir.pointer_type(@lir.struct_type(ARRAY_STRUCT))

    def zero_value(type)
      return @lir.create_const_bool(false) if type == :bool
      return @lir.create_brace_init([], type) if type.is_a?(Hash) && type[:kind] != :pointer

      @lir.create_const_int(0, type == :int64 ? :int64 : :int32)
    end
  end
end
