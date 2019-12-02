module GarnetRuby
  class Iseq
    CatchRecord = Struct.new(:type, :st, :ed, :cont, :iseq)

    attr_reader :name,
                :type,
                :instructions,
                :local_table,
                :catch_table,
                :parent_iseq,
                :local_iseq

    attr_accessor :start_label, :end_label, :redo_label

    def initialize(name, type, parent = nil, local_table = {})
      @name = name
      @type = type
      @instructions = []
      @local_table = local_table
      @catch_table = []
      set_relation(parent)
    end

    def add_instruction(type, *args)
      Instruction.new(type, *args).tap do |insn|
        @instructions << insn
      end
    end

    def add_catch_type(type, st, ed, cont, iseq)
      @catch_table << CatchRecord.new(type, st, ed, cont, iseq)
    end

    def to_s
      name
    end

    def inspect
      "#<Iseq:#{name}>"
    end

    def debug_dump_instructions
      @instructions.each_with_index do |insn, i|
        args = insn.arguments
                   .map { |x| x.is_a?(String) ? x.inspect : x.to_s }
                   .join(',')
        puts "#{i}: #{insn.type}\t#{args}"
      end
    end

    def local_level(label)
      i = self
      l = local_iseq
      lv = 0
      while i != l && !i.local_table.key?(label)
        break if i.parent_iseq.nil?

        i = i.parent_iseq
        lv += 1
      end
      lv
    end

    private

    def set_relation(piseq)
      case type
      when :top, :method, :class, :main
        @local_iseq = self
      else
        @local_iseq = piseq.local_iseq if piseq
      end

      @parent_iseq = piseq if piseq
    end
  end
end