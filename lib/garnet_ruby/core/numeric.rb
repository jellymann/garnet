module GarnetRuby
  module Core
    class << self
      def fixnum?(value)
        value.is_a?(RPrimitive) && value.type?(Integer)
      end

      def modf(x)
        i = x.floor
        f = x - i
        [f, i]
      end

      def integer_float_eq(x, y)
        yd = y.value
        return Q_FALSE if yd.nan? || yd.infinite?

        yf, yi = modf(yd)
        return Q_FALSE unless yf.zero?
        return Q_TRUE if yi == x.value

        Q_FALSE
      end

      def num_equal(x, y)
        return Q_TRUE if x == y

        rtest(rb_funcall(y, :==, x))
      end

      def fix_equal(x, y)
        return Q_TRUE if x == y

        if fixnum?(y)
          Q_FALSE
        elsif y.type?(Float)
          integer_float_eq(x, y)
        else
          num_equal(x, y)
        end
      end

      def int_equal(x, y)
        if fixnum?(x)
          fix_equal(x, y)
        else
          Q_NIL
        end
      end

      def integer_float_cmp(x, y)
        yd = y.value
        return Q_NIL if yd.nan?

        return RPrimitive.from(yd > 0.0 ? -1 : 1) if yd.infinite?

        yf, yi = modf(yd)
        xn = x.value
        return RPrimitive.from(-1) if xn < yi
        return RPrimitive.from(1) if xn > yi
        return RPrimitive.from(1) if yf < 0.0
        return RPrimitive.from(-1) if yf > 0.0
        RPrimitive.from(0)
      end

      def rb_cmperr(x, y)
        classname = if y.type?(Symbol) || y.type?(Float)
                      rb_funcall(y, :inspect)
                    else
                      y.klass
                    end
        rb_raise(eArgError, "comparison of #{x.klass} with #{classname} failed")
      end

      def coerce_failed(x, y)
        y = if y.type?(Symbol) || y.type?(Float)
              rb_funcall(y, :inspect)
            else
              y.klass
            end
        rb_raise(eTypeError, "#{y} can't be coerced into #{x.klass}")
      end

      def do_coerce(x, y, err)
        ary = rb_check_funcall(y, :coerce, x)
        if ary == Q_UNDEF
          coerce_failed if err
          return false
        end
        return false if !err && ary == Q_NIL

        if ary.is_a?(RArray) || ary.array_value.length != 2
          rb_raise(eTypeError, 'coerce must return [x, y]')
          return false
        end

        ary.array_value
      end

      def num_coerce_relop(x, y, func)
        coerse = do_coerce(x, y, false)

        if !coerse || (c = rb_funcall(coerse[0], func, coerse[1])) == Q_NIL
          rb_cmperr(x, y)
          return Q_NIL
        end
        c
      end

      def fix_gt(x, y)
        if fixnum?(y)
          return Q_TRUE if x.value > y.value

          Q_FALSE
        elsif y.type?(Float)
          integer_float_cmp(x, y).value == 1 ? Q_TRUE : Q_FALSE
        else
          num_coerce_relop(x, y, :>)
        end
      end

      def int_gt(x, y)
        if fixnum?(x)
          fix_gt(x, y)
        else
          Q_NIL
        end
      end

      def fix_ge(x, y)
        if fixnum?(y)
          return Q_TRUE if x.value >= y.value

          Q_FALSE
        elsif y.type?(Float)
          rel = integer_float_cmp(x, y)
          rel.value == 1 || rel.value.zero? ? Q_TRUE : Q_FALSE
        else
          num_coerce_relop(x, y, :>=)
        end
      end

      def int_ge(x, y)
        if fixnum?(x)
          fix_ge(x, y)
        else
          Q_NIL
        end
      end

      def fix_lt(x, y)
        if fixnum?(y)
          return Q_TRUE if x.value < y.value

          Q_FALSE
        elsif y.type?(Float)
          integer_float_cmp(x, y).value == -1 ? Q_TRUE : Q_FALSE
        else
          num_coerce_relop(x, y, :<)
        end
      end

      def int_lt(x, y)
        if fixnum?(x)
          fix_lt(x, y)
        else
          Q_NIL
        end
      end

      def fix_le(x, y)
        if fixnum?(y)
          return Q_TRUE if x.value <= y.value

          Q_FALSE
        elsif y.type?(Float)
          rel = integer_float_cmp(x, y)
          rel.value == -1 || rel.value.zero? ? Q_TRUE : Q_FALSE
        else
          num_coerce_relop(x, y, :<=)
        end
      end

      def int_le(x, y)
        if fixnum?(x)
          fix_le(x, y)
        else
          Q_NIL
        end
      end
    end

    def self.init_numeric
      @cNumeric = rb_define_class(:Numeric, cObject)

      @cInteger = rb_define_class(:Integer, cNumeric)
      rb_define_method(cInteger, :+) do |x, y|
        # TODO: type coersion
        RPrimitive.new(cInteger, 0, x.value + y.value)
      end
      rb_define_method(cInteger, :to_s) do |x, base = 10|
        RString.new(cString, 0, x.value.to_s(base))
      end
      rb_alias_method(cInteger, :inspect, :to_s)
      rb_define_method(cInteger, :===, &method(:int_equal))
      rb_define_method(cInteger, :==, &method(:int_equal))
      rb_define_method(cInteger, :>, &method(:int_gt))
      rb_define_method(cInteger, :>=, &method(:int_ge))
      rb_define_method(cInteger, :<, &method(:int_lt))
      rb_define_method(cInteger, :<=, &method(:int_le))
    end
  end
end
