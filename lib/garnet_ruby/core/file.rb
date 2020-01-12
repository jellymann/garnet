module GarnetRuby
  class RFile < RIO
    def initialize(klass, flags, file_value)
      super(klass, flags, file_value)
    end

    def self.from(file)
      return Q_NIL if file.nil?

      new(Core.cFile, [], file)
    end

    def self.open(filename, mode="r", perm = nil, opt = nil)
      m = if mode.type?(Integer)
            mode.value
          else
            mode.string_value
          end

      # TODO: perm and opt
      from(File.new(filename.string_value, m))
    end
  end

  module Core
    class << self
      def rb_get_path(obj)
        return obj if obj.type?(String)
        tmp = rb_check_funcall_default(obj, :to_path, obj)
        tmp.str_to_str
      end

      def file_s_unlink(_, *args)
        args.each { |f| File.unlink(f.string_value) }
      end

      def file_s_expand_path(_, *args)
        if args.length == 1
          RString.from(File.expand_path(rb_get_path(args[0]).string_value))
        else
          RString.from(File.expand_path(rb_get_path(args[0]).string_value, rb_get_path(args[1]).string_value))
        end
      end

      def file_s_basename(_, *args)
        if args.length == 1
          RString.from(File.basename(rb_get_path(args[0]).string_value))
        else
          RString.from(File.basename(rb_get_path(args[0]).string_value, args[1].obj_as_string.string_value))
        end
      end

      def file_s_dirname(_, fname)
        RString.from(File.dirname(rb_get_path(fname).string_value))
      end

      def define_filetest_function(name)
        x = -> (_, *args) { File.__send__(name, *args.map(&:string_value)) ? Q_TRUE : Q_FALSE }
        rb_define_module_function(mFileTest, name, &x)
        rb_define_singleton_method(cFile, name, &x)
      end
    end

    def self.init_file
      @mFileTest = rb_define_module(:FileTest)
      @cFile = rb_define_class(:File, cIO)

      define_filetest_function(:directory?)
      define_filetest_function(:exist?)
      define_filetest_function(:exists?)
      define_filetest_function(:readable?)
      define_filetest_function(:readable_real?)
      define_filetest_function(:world_readable?)
      define_filetest_function(:writable?)
      define_filetest_function(:writable_real?)
      define_filetest_function(:world_writable?)
      define_filetest_function(:executable?)
      define_filetest_function(:executable_real?)
      define_filetest_function(:file?)
      define_filetest_function(:zero?)
      define_filetest_function(:empty?)
      define_filetest_function(:size?)
      define_filetest_function(:size)
      define_filetest_function(:owned?)
      define_filetest_function(:grpowned?)

      define_filetest_function(:pipe?)
      define_filetest_function(:symlink?)
      define_filetest_function(:socket?)

      define_filetest_function(:blockdev?)
      define_filetest_function(:chardev?)

      define_filetest_function(:setuid?)
      define_filetest_function(:setgid?)
      define_filetest_function(:sticky?)

      define_filetest_function(:identical?)

      rb_define_singleton_method(cFile, :unlink, &method(:file_s_unlink))
      rb_define_singleton_method(cFile, :expand_path, &method(:file_s_expand_path))
      rb_define_singleton_method(cFile, :basename, &method(:file_s_basename))
      rb_define_singleton_method(cFile, :dirname, &method(:file_s_dirname))
    end
  end
end
