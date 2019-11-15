module RubyRuby
  module Core
    def self.init_io
      rb_define_global_function(:puts) do |_, *args|
        # TODO: stdout.puts

        if args.empty?
          print("\n")
          return Q_NIL
        end

        args.each do |arg|
          print Core.rb_funcall(arg, :to_s).string_value
          print "\n"
        end

        Q_NIL
      end
    end
  end
end
