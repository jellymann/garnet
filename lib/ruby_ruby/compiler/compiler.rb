module RubyRuby
  class Compiler
    def initialize(iseq)
      @iseq = iseq
    end

    def compile_node(node)
      compile(node)
      add_instruction(:leave) unless @iseq.instructions.last&.type == :leave

      puts "Iseq:#{@iseq.name}"
      puts "local table: #{@iseq.local_table}"
      @iseq.debug_dump_instructions
      puts
    end

    def compile(node)
      method_name = :"compile_#{node[0]}"
      raise "COMPILE_ERROR: Unknown Node Type #{node[0]}" unless respond_to?(method_name)

      __send__(method_name, node)
    end

    def compile_lit(node)
      case node[1]
      when Integer
        add_instruction(:put_object, RPrimitive.new(Core.cInteger, 0, node[1]))
      when Float
        add_instruction(:put_object, RPrimitive.new(Core.cFloat, 0, node[1]))
      when Range
        # TODO
      when Regexp
        # TODO
      else
        raise "UNKNOWN_LITERAL: #{node[1].inspect}"
      end
    end

    def compile_block(node)
      node[1..-2].each do |n|
        compile(n)
        add_instruction(:pop)
      end
      compile(node[-1])
    end

    def compile_true(node)
      add_instruction(:put_object, Q_TRUE)
    end

    def compile_false(node)
      add_instruction(:put_object, Q_FALSE)
    end

    def compile_nil(node)
      add_instruction(:put_object, Q_NIL)
    end

    def compile_self(node)
      add_instruction(:put_self)
    end

    def compile_str(node)
      add_instruction(:put_object, RString.new(Core.cString, 0, node[1]))
    end

    def compile_or(node)
      compile(node[1])
      add_instruction(:dup)
      jump_insn = add_instruction(:branch_if, nil)
      add_instruction(:pop)
      compile(node[2])
      jump_insn.arguments[0] = @iseq.instructions.length
    end

    def compile_lvar(node)
      add_instruction(:get_local, node[1], @iseq.local_level)
    end

    def compile_lasgn(node)
      compile(node[2])
      add_instruction(:set_local, node[1], @iseq.local_level)
    end

    def compile_cdecl(node)
      compile(node[2])
      add_instruction(:set_constant, node[1])
    end

    def compile_const(node)
      add_instruction(:get_constant, node[1])
    end

    def compile_gasgn(node)
      compile(node[2])
      add_instruction(:set_global, node[1])
    end

    def compile_gvar(node)
      add_instruction(:get_global, node[1])
    end

    def compile_defn(node)
      mid = node[1]
      args = node[2]
      nodes = node[3..-1]

      local_table = args[1..-1].map { |a| [a, :arg] }.to_h
      method_iseq = Iseq.new(mid.to_s, :method, @iseq, local_table)
      compiler = Compiler.new(method_iseq)
      nodes.each do |n|
        compiler.compile_node(n)
      end

      add_instruction(:put_object, RSymbol.new(Core.cSymbol, 0, mid))
      add_instruction(:put_iseq, method_iseq)
      add_instruction(:define_method)
    end

    def compile_call(node)
      if node[1]
        compile(node[1])
      else
        add_instruction(:put_self)
      end
      argc = compile_args(node)
      add_instruction(:send, node[2], argc)
    end

    def compile_args(node)
      argc = node.length - 3
      node[3..-1].each do |n|
        compile(n)
      end
      argc
    end

    def add_instruction(type, *args)
      @iseq.add_instruction(type, *args)
    end
  end
end
