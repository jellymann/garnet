module GarnetRuby
  module Core
    class << self
      def enum_to_a(obj)
        ary = RArray.from([])

        rb_block_call(obj, :each) do |x|
          ary.array_value.push(x)
        end

        ary
      end
    end

    def self.init_enum
      @mEnumerable = rb_define_module(:Enumerable)

      rb_define_method(mEnumerable, :to_a, &method(:enum_to_a))
    end
  end
end