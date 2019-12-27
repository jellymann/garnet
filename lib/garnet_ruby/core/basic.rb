module GarnetRuby
  class RBasic
    attr_accessor :klass, :flags

    def initialize(klass, flags)
      @klass = klass
      @flags = flags
    end

    def to_s
      "<##{klass.name}>"
    end
    alias inspect to_s

    def type
      nil
    end

    def type?(_)
      false
    end

    def discrete_object?
      return false if obj_is_kind_of(self, Core.cTime) == Q_TRUE # TODO: until Time#succ removed
      VM.instance.rb_respond_to(self, :succ)
    end

    def obj_as_string
      return self if type?(String)

      str = Core.rb_funcall(self, :to_s)
      str.obj_as_string_result(self)
    end

    def obj_as_string_result(obj)
      return obj.any_to_s unless type?(String)

      self
    end

    def any_to_s
      "<#{self.klass.name}:#{self.__id__}>"
    end

    def check_string_type
      rb_check_convert_type_with_id(String, "String", :to_str)
    end

    def str_to_str
      rb_convert_type_with_id(String, "String", :to_str)
    end

    def to_array_type
      rb_convert_type_with_id(Array, "Array", :to_ary)
    end

    def check_array_type
      rb_check_convert_type_with_id(Array, "Array", :to_ary)
    end

    def check_to_array
      rb_check_convert_type_with_id(Array, "Array", :to_a)
    end

    def rb_check_convert_type_with_id(type, tname, method)
      return self if self.type == type
      v = convert_type_with_id(tname, method, false, -1)
      return Q_NIL if v == Q_NIL
      if v.type != type
        conversion_mismatch(tname, method, v)
      end
      v
    end

    def rb_convert_type_with_id(type, tname, method)
      return self if self.type == type
      v = convert_type_with_id(tname, method, true, -1)
      if v.type != type
        conversion_mismatch(tname, method, v)
      end
      v
    end

    def convert_type_with_id(tname, method, should_raise, index)
      r = VM.instance.rb_check_funcall(self, method)
      if r == Q_UNDEF
        if should_raise
          # TODO: fancier error message
          
          cname = case self
          when Q_NIL   then "nil"
          when Q_TRUE  then "true"
          when Q_FALSE then "false"
          else self.klass
          end
          raise TypeError, "can't convert #{cname} into #{tname}"
        end
        return Q_NIL
      end
      r
    end

    def conversion_mismatch(tname, method, result)
      cname = self.klass
      raise TypeError, "can't convert #{cname} to #{tname} (#{cname}##{method} gives #{result.klass})"
    end
  end
end
