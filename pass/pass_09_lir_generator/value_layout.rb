# frozen_string_literal: true

module BareRubyProt
  # How a BareRuby value is represented once the types are gone: which low-level type it
  # becomes, which struct has to be declared for it, and where the parts of that struct
  # are reached. A struct is declared once however many times the type appears, so this
  # holds the ones it has already answered for and hands out the same one again.
  class ValueLayout
    STRING_STRUCT = :bareruby_string_t

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

    def field_name(name) = name.to_s.delete_prefix("@").to_sym

    private

    def struct_type_of(type)
      case type[:kind]
      when :array then array_struct_type(type)
      when :arena_array then arena_array_struct_type(type)
      when :arena_string then arena_string_type
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

    # An arena array is a pointer into the region plus the length that was asked for, so
    # assigning one shares the allocation the way assigning an array does, and the
    # capacity the compiler cannot know is carried at run time. That is why the handle
    # itself is not a shared type: both of its fields are settled when the allocation is
    # made and nothing afterwards changes them, so a copy of the handle still names the
    # same elements, and the method that allocated it can hand it back — where a pointer
    # to it would outlive the local it pointed at.
    def arena_array_struct_type(type)
      raise "the element type of this arena array was never determined" if type[:element].nil?

      element = type_of(type[:element])
      name = :"bareruby_arena_array_#{element}_t"
      @array_structs[name] ||= @lir.create_struct(
        name, [@lir.create_field(:items, @lir.pointer_type(element)), @lir.create_field(:length, :int32)]
      )
      @lir.struct_type(name)
    end

    def zero_value(type)
      return @lir.create_const_bool(false) if type == :bool
      return @lir.create_brace_init([], type) if type.is_a?(Hash) && type[:kind] != :pointer

      @lir.create_const_int(0, type == :int64 ? :int64 : :int32)
    end
  end
end
