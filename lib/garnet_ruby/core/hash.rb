module GarnetRuby
  class RHash < RObject
    attr_reader :table

    def initialize(klass, flags)
      super(klass, flags)
      @table = {}
    end

    def type
      Hash
    end

    def type?(x)
      x == Hash
    end

    def self.from(h)
      return Q_NIL if h.nil?

      hsh = new(Core.cHash, [])
      h.each do |k, v|
        key = Core.ruby2garnet(k)
        value = Core.ruby2garnet(v)

        Core.hash_aset(hsh, key, value)
      end
      hsh
    end

    def entries
      @table.values.flatten
    end

    def size
      entries.length
    end

    class Entry
      attr_reader :key
      attr_accessor :value

      def initialize(key, value)
        @key = key
        @value = value
      end

      def hash_code
        Core.rb_funcall(key, :hash).value ^ Core.rb_funcall(value, :hash).value
      end
    end
  end

  module Core
    class << self
      def hash_inspect(hash)
        strings = hash.entries.map do |e|
          [rb_funcall(e.key, :inspect).string_value, rb_funcall(e.value, :inspect).string_value]
        end.to_h
        RString.from("{#{strings.map { |k, v| "#{k}=>#{v}" }.join(', ')}}")
      end

      def hash_aset(hash, k, v)
        kh = rb_funcall(k, :hash).value
        entries = hash.table[kh] ||= []
        entry = entries.find { |e| rtest(rb_funcall(e.key, :eql?, k)) }
        if entry
          entry.value = v
        else
          entries << RHash::Entry.new(k, v)
        end
      end

      def hash_aref(hash, k)
        kh = rb_funcall(k, :hash).value
        entry = hash.table[kh]&.find { |e| rtest(rb_funcall(e.key, :eql?, k)) }
        entry&.value || Q_NIL
      end

      def hash_has_key(hash, k)
        kh = rb_funcall(k, :hash).value
        entries = hash.table[kh]
        return Q_FALSE unless entries

        entries.any? { |e| rtest(rb_funcall(e.key, :eql?, k)) } ? Q_TRUE : Q_FALSE
      end

      def hash_equal(hash1, hash2)
        hash_equal_internal(hash1, hash2, false)
      end

      def hash_eql(hash1, hash2)
        hash_equal_internal(hash1, hash2, true)
      end

      def hash_equal_internal(hash1, hash2, eql)
        return Q_TRUE if hash1 == hash2

        if !hash2.type?(Hash)
          if !VM.instance.rb_respond_to(hash2, :to_hash)
            return Q_FALSE
          end
          if eql
            return rb_eql(hash2, hash1)
          else
            return rb_equal(hash2, hash1)
          end
        end
        return Q_FALSE if hash1.entries.size != hash2.entries.size
        return Q_TRUE if hash1.entries.empty? && hash2.entries.empty?

        hash1.entries.each do |e|
          return Q_FALSE unless rtest(hash_has_key(hash2, e.key))

          value2 = hash_aref(hash2, e.key)
          result = eql ? rb_eql(e.value, value2) : rb_equal(e.value, value2)
          return Q_FALSE unless rtest(result)
        end

        Q_TRUE
      end

      def hash_hash(hash)
        RPrimitive.from(hash.entries.reduce(0) { |h, e| h + e.hash_code })
      end

      def hash_values(hash)
        RArray.from(hash.entries.map { |e| e.value })
      end
    end

    def self.init_hash
      @cHash = rb_define_class(:Hash)

      rb_define_method(cHash, :inspect, &method(:hash_inspect))
      rb_alias_method(cHash, :to_s, :inspect)

      rb_define_method(cHash, :==, &method(:hash_equal))
      rb_define_method(cHash, :[], &method(:hash_aref))
      rb_define_method(cHash, :hash, &method(:hash_hash))
      rb_define_method(cHash, :eql?, &method(:hash_eql))
      rb_define_method(cHash, :[]=, &method(:hash_aset))
    end
  end
end
