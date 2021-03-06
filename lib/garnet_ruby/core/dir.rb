module GarnetRuby
  module Core
    class << self
      def check_dirname(dir)
        # TODO
        rb_get_path(dir)
      end

      def dir_s_getwd(_)
        RString.from(Dir.pwd)
      end

      def dir_s_mkdir(_, *args)
        path, vmode = args
        mode = if args.length == 2
                 num2long(vmode)
               else
                 0777
               end

        path = check_dirname(path)
        Dir.mkdir(path.string_value, mode)

        RPrimitive.from(0)
      end

      def dir_s_rmdir(obj, dir)
        dir = check_dirname(dir)

        Dir.delete(dir.string_value)

        RPrimitive.from(0)
      rescue SystemCallError => e
        rb_raise(@syserr_tbl[e.errno], e.message)
      end

      def dir_s_aref(_, *args)
        RArray.from(Dir[*args.map{ |s| s.obj_as_string.string_value }])
      rescue SystemCallError => e
        rb_raise(@syserr_tbl[e.errno], e.message)
      end

      def dir_s_exist(_, fname)
        tmp = fname.rb_check_convert_type_with_id(File, 'IO', :to_io)
        if tmp != Q_NIL
          Dir.exist?(tmp.file_value) ? Q_TRUE : Q_FALSE
        else
          fname = rb_get_path(fname)
          Dir.exist?(fname.string_value) ? Q_TRUE : Q_FALSE
        end
      end
    end

    def self.init_dir
      @cDir = rb_define_class(:Dir, cObject)

      rb_define_singleton_method(cDir, :pwd, &method(:dir_s_getwd))
      rb_define_singleton_method(cDir, :mkdir, &method(:dir_s_mkdir))
      rb_define_singleton_method(cDir, :rmdir, &method(:dir_s_rmdir))
      rb_define_singleton_method(cDir, :delete, &method(:dir_s_rmdir))
      rb_define_singleton_method(cDir, :unlink, &method(:dir_s_rmdir))

      rb_define_singleton_method(cDir, :[], &method(:dir_s_aref))
      rb_define_singleton_method(cDir, :exist?, &method(:dir_s_exist))
    end
  end
end
