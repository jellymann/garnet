module GarnetRuby
  class Compiler
    class CallInfo
      attr_reader :mid, :argc, :flags, :block_iseq

      def initialize(mid, argc, flags, block_iseq = nil)
        @mid = mid
        @argc = argc
        @flags = flags
        @block_iseq = block_iseq
      end

      def inspect
        things = [
          mid && "mid:#{mid}",
          "argc:#{argc}",
          flags.map { |f| f.to_s.upcase}.join('|'),
          block_iseq
        ].compact.join(', ')
        "<callinfo!#{things}>"
      end
      alias to_s inspect
    end

    class Label
      attr_reader :line

      def initialize(iseq)
        @iseq = iseq
        @insns = []
        @line = nil
      end

      def add
        @line = @iseq.instructions.length
        @insns.each do |insns|
          insns.arguments[0] = @line
        end
        @insns = nil
      end

      def ref(ins)
        if @line
          ins.arguments[0] = @line
        else
          @insns << ins
        end
      end
    end

    def initialize(iseq)
      @iseq = iseq
    end

    def compile_nodes(nodes)
      nodes.each do |node|
        compile(node)
      end

      add_instruction(:leave) unless @iseq.instructions.last&.type == :leave

      puts "Iseq:#{@iseq.name}"
      puts "local table: #{@iseq.local_table}"
      @iseq.debug_dump_instructions
      puts
    end

    def compile_node(node)
      compile_nodes([node])
    end

    def compile(node)
      method_name = :"compile_#{node[0]}"
      raise "COMPILE_ERROR: Unknown Node Type #{node[0]} (#{node.file}:#{node.line})" unless respond_to?(method_name)

      __send__(method_name, node)
    end

    def compile_lit(node)
      case node[1]
      when Integer
        add_instruction(:put_object, RPrimitive.new(Core.cInteger, 0, node[1]))
      when Float
        add_instruction(:put_object, RPrimitive.new(Core.cFloat, 0, node[1]))
      when Symbol
        add_instruction(:put_object, RSymbol.new(Core.cSymbol, 0, node[1]))
      when Range
        # TODO
      when Regexp
        add_instruction(:put_object, RRegexp.new(Core.cRegexp, 0, node[1]))
      else
        raise "UNKNOWN_LITERAL: #{node[1].inspect} (#{node.file}:#{node.line})"
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
      add_instruction(:put_nil)
    end

    def compile_self(node)
      add_instruction(:put_self)
    end

    def compile_str(node)
      add_instruction(:put_string, node[1])
    end

    def compile_dstr(node)
      node[1..-1].each do |n|
        case n
        when String
          add_instruction(:put_string, n)
        else
          compile(n)
        end
      end
      add_instruction(:concat_strings, node.length - 1)
    end

    def compile_evstr(node)
      compile(node[1])
      add_instruction(:send_without_block, CallInfo.new(:to_s, 0, [:simple]))
    end

    def compile_array(node)
      if node.length == 1
        add_instruction(:new_array, 0)
        return
      end
      chunks = node[1..-1].chunk { |n| n[0] == :splat }.to_a
      if chunks[0][0]
        compile(chunks[0][1][0][1])
        add_instruction(:splat_array, true)
        chunks.slice!(0)
      else
        nodes = chunks.slice!(0)[1]
        array_from_nodes(nodes)
      end
      chunks.each do |splat, n|
        if splat
          compile(n[0][1])
        else
          array_from_nodes(n)
        end
        add_instruction(:concat_array)
      end
    end

    def compile_svalue(node)
      compile(node[1][1])
      add_instruction(:splat_array, true)
    end

    def array_from_nodes(nodes)
      nodes.each do |n|
        compile(n)
      end
      add_instruction(:new_array, nodes.count)
    end

    def compile_masgn(node)
      locals = node[1][1..-1]
      case node[2][0]
      when :to_ary
        compile(node[2][1])
        add_instruction(:dup)
      when :splat
        compile(node[2][1])
        add_instruction(:splat_array, true)
        add_instruction(:dup)
      when :array
        compile(node[2])
        add_instruction(:dup)
      end
      i = locals.index { |l| l[0] == :splat}
      if i.nil?
        add_instruction(:expand_array, locals.count, false, false)
      else
        pre = locals[0...i]
        splat = locals[i]
        post = locals[(i + 1)..-1]

        add_instruction(:expand_array, pre.count, true, false)
        pre.each do |l|
          add_set_local(l[1])
        end
        if post.empty?
          add_set_local(splat[1][1])
        else
          add_instruction(:expand_array, post.count, true, true)
          add_set_local(splat[1][1])
          post.each do |l|
            add_set_local(l[1])
          end
        end
      end
    end

    def compile_hash(node)
      node[1..-1].each do |n|
        compile(n)
      end
      add_instruction(:new_hash, node.length - 1)
    end

    def compile_or(node)
      compile_boolean_op(node, :branch_if)
    end

    def compile_and(node)
      compile_boolean_op(node, :branch_unless)
    end

    def compile_boolean_op(node, branch_type)
      end_label = new_label

      compile(node[1])
      add_instruction(:dup)
      add_instruction_with_label(branch_type, end_label)
      add_instruction(:pop)
      compile(node[2])
      add_label(end_label)
    end

    def compile_if(node)
      else_label = new_label
      end_label = new_label

      cond, if_branch, else_branch = node[1..3]
      compile(cond)
      add_instruction_with_label(:branch_unless, else_label)
      compile(if_branch || [:nil])
      add_instruction_with_label(:jump, end_label)
      add_label(else_label)
      compile(else_branch || [:nil])
      add_label(end_label)
    end

    def compile_case(node)
      *whens, else_block = node[2..-1]
      else_block ||= [:nil]

      when_labels = whens.map { new_label }
      end_label = new_label

      compile(node[1])

      whens.each_with_index do |w, i|
        w[1][1..-1].each do |c|
          add_instruction(:dup)
          flags = []

          if c[0] == :splat
            compile(c[1])
            add_instruction(:splat_array, false)
            flags << :array
          else
            compile(c)
          end

          add_instruction(:check_match, :case, flags)
          add_instruction_with_label(:branch_if, when_labels[i])
        end
      end

      add_instruction(:pop)
      compile(else_block)
      add_instruction_with_label(:jump, end_label)

      whens.each_with_index do |w, i|
        add_label(when_labels[i])
        add_instruction(:pop)

        w[2..-2].each do |n|
          compile(n)
          add_instruction(:pop)
        end

        compile(w[-1])

        unless i == whens.length - 1
          add_instruction_with_label(:jump, end_label)
        end
      end

      add_label(end_label)
    end

    def compile_while(node)
      compile_loop(node, :branch_if)
    end

    def compile_until(node)
      compile_loop(node, :branch_unless)
    end

    def compile_loop(node, branch_type)
      cond, body = node[1..2]

      prev_start_label = @iseq.start_label
      prev_redo_label = @iseq.redo_label

      next_label = @iseq.start_label = new_label
      redo_label = @iseq.redo_label = new_label
      end_label = new_label

      # TODO: figure out what the hell this is supposed to be...
      add_instruction_with_label(:jump, next_label)
      add_instruction(:put_nil)
      add_instruction(:pop)
      add_instruction_with_label(:jump, next_label)

      add_label(redo_label)
      compile(body)
      add_instruction(:pop)

      add_label(next_label)
      compile(cond)
      add_instruction_with_label(branch_type, redo_label)

      add_instruction(:put_nil)

      add_label(end_label)
      add_instruction(:nop)

      @iseq.add_catch_type(:break, redo_label.line, end_label.line, end_label.line, @iseq)

      @iseq.start_label = prev_start_label
      @iseq.redo_label = prev_redo_label
    end

    def compile_lvar(node)
      add_get_local(node[1])
    end

    def compile_lasgn(node)
      compile(node[2])
      add_set_local(node[1])
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
      compiler.compile_nodes(nodes)

      add_instruction(:put_object, RSymbol.new(Core.cSymbol, 0, mid))
      add_instruction(:put_iseq, method_iseq)
      add_instruction(:define_method)
    end

    def compile_return(node)
      compile(node[1]) if node.length > 1
      add_instruction(:leave)
      # TODO: handle blocks
    end

    def compile_next(node)
      if @iseq.redo_label
        compile(node[1] || [:nil])
        add_instruction(:pop)
        add_instruction_with_label(:jump, @iseq.start_label)
      else
        compile(node[1]) if node.length > 1
        add_instruction(:leave)
      end
    end

    def compile_break(node)
      compile(node[1]) if node.length > 1
      add_instruction(:throw, :break)
    end

    def compile_call(node)
      if node[1]
        compile(node[1])
      else
        add_instruction(:put_self)
      end
      argc, flags = compile_call_args(node)
      add_instruction(:send_without_block, CallInfo.new(node[2], argc, flags))
    end

    def compile_yield(node)
      argc, flags = compile_args(node[1..-1])
      add_instruction(:invoke_block, CallInfo.new(nil, argc, flags))
    end

    def compile_iter(node)
      st = @iseq.instructions.length - 1

      block_args = node[2] == 0 ? [:args] : node[2]
      local_table = block_args[1..-1].map { |a| [a, :arg] }.to_h
      block_iseq = Iseq.new("block in #{@iseq.name}", :block, @iseq, local_table)
      compiler = Compiler.new(block_iseq)
      compiler.compile_node(node[3])

      call_node = node[1]
      if call_node[1]
        compile(call_node[1])
      else
        add_instruction(:put_self)
      end
      argc, flags = compile_call_args(call_node)

      add_instruction(:send, CallInfo.new(call_node[2], argc, flags, block_iseq))
      add_instruction(:nop)

      ed = @iseq.instructions.length - 1
      @iseq.add_catch_type(:break, st, ed, ed, block_iseq)
    end

    def compile_attrasgn(node)
      add_instruction(:put_nil)
      compile(node[1])
      argc, flags = compile_call_args(node)
      add_instruction(:setn, argc + 1)
      add_instruction(:send_without_block, CallInfo.new(node[2], argc, flags))
    end

    def compile_op_asgn_or(node)
      compile_op_asgn_or_and(node, :branch_if)
    end

    def compile_op_asgn_and(node)
      compile_op_asgn_or_and(node, :branch_unless)
    end

    def compile_op_asgn_or_and(node, branch_type)
      end_label = new_label

      compile(node[1])
      add_instruction(:dup)
      add_instruction_with_label(branch_type, end_label)
      add_instruction(:pop)
      compile(node[2][2])
      add_instruction(:dup)
      add_set_local(node[2][1])

      add_label(end_label)
    end

    def compile_op_asgn1(node)
      match_label = new_label
      end_label = new_label

      add_instruction(:put_nil)
      compile(node[1])
      argc, flags = compile_argslist(node[2])
      add_instruction(:dupn, argc + 1)
      add_instruction(:send_without_block, CallInfo.new(:[], argc, [:simple]))
      case node[3]
      when :'||', :'&&'
        add_instruction(:dup)
        add_instruction_with_label(node[3] == :'&&' ? :branch_unless : :branch_if, match_label)
        add_instruction(:pop)
        compile(node[4])
        add_instruction(:send_without_block, CallInfo.new(:[]=, argc + 1, flags))
        add_instruction(:pop)
        add_instruction_with_label(:jump, end_label)
        add_label(match_label)
        add_instruction(:setn, argc + 2)
        add_instruction(:adjust_stack, argc + 2)
        add_label(end_label)
      else
        compile(node[4])
        add_instruction(:send_without_block, CallInfo.new(node[3], 1, [:simple]))
        add_instruction(:setn, argc + 2)
        add_instruction(:send_without_block, CallInfo.new(:[]=, argc + 1, flags))
        add_instruction(:pop)
      end
    end

    def compile_match2(node)
      # TODO: compile to optimised regexp_match instruction
      compile_regex_match(node)
    end

    def compile_match3(node)
      # TODO: compile to optimised regexp_match instruction
      compile_regex_match(node)
    end

    def compile_regex_match(node)
      left, right = node[1..2]
      compile(left)
      compile(right)
      add_instruction(:send_without_block, CallInfo.new(:=~, 1, [:simple]))
    end

    def compile_call_args(node)
      compile_args(node[3..-1])
    end

    def compile_argslist(node)
      compile_args(node[1..-1])
    end

    def compile_args(args)
      flags = []
      has_splat = args.find { |x| x[0] == :splat }
      slices = args.slice_when { |a, b| a[0] == :splat || b[0] == :splat }.to_a
      count = 0
      if has_splat
        if slices[0][0][0] == :splat
          pargs = []
        else
          pargs = slices[0]
          slices = slices[1..-1]
        end
        count = pargs.count + 1
        flags << :splat
      else
        pargs = args
        count = pargs.count
        flags << :simple
      end
      pargs.each do |n|
        compile(n)
      end
      if has_splat
        slices.each_with_index do |slice, index|
          if slice[0][0] == :splat
            compile(slice[0][1])
            add_instruction(:splat_array, index != slices.count - 1)
          else
            slice.each do |a|
              compile(a)
            end
            add_instruction(:new_array, slice.count)
          end
        end
        (slices.count - 1).times do
          add_instruction(:concat_array)
        end
      end
      [count, flags]
    end

    def new_label
      Label.new(@iseq)
    end

    def add_label(label)
      label.add
    end

    def add_instruction(type, *args)
      @iseq.add_instruction(type, *args)
    end

    def add_instruction_with_label(type, label)
      @iseq.add_instruction(type, nil).tap { |i| label.ref(i) }
    end

    def add_set_local(name)
      add_instruction(:set_local, name, @iseq.local_level(name))
    end

    def add_get_local(name)
      add_instruction(:get_local, name, @iseq.local_level(name))
    end
  end
end
