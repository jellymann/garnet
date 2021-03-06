# frozen_string_literal: true

require 'optparse'
require 'pp'

$__grb_debug__ = false

def __grb_debug__?
  $__grb_debug__ || ENV['GARNET_DEBUG']
end

module GarnetRuby
  class Error < StandardError; end

  Q_UNDEF = Object.new

  def self.parse_options(argv=ARGV, options={})
    OptionParser.new do |opts|
      opts.banner = "Usage: garnet [switches] [--] [progfile] [arguments]"

      opts.on('-d', '--debug', 'set debugging flags') do |v|
        $__grb_debug__ = options[:debug] = v
      end

      opts.on("-e 'command'", "one line of script. Several -e's allowed. Omit [programfile]") do |v|
        options[:script_name] = '-e'
        if options[:source]
          options[:source] += "\n#{v}"
        else
          options[:source] = v
        end
      end

      opts.on('-s', 'enable some switch parsing for switches after script name') do |v|
        options[:switch_parsing] = v
      end
      
      opts.on('-x', 'strip off text before #!ruby line') do |v|
        options[:strip_before_crunchbang] = v
      end

      opts.on("-v", "--version", "print the version number, then exit") do
        puts "garnet #{VERSION}"
        exit
      end

      opts.on("-h", "--help", "show this message") do
        puts opts
        exit
      end
    end.order!(argv) do |v|
      argv.unshift(v)
      break
    end

    if !options[:script_name]
      if argv.empty?
        options[:script_name] = '-'
        options[:source] = STDIN.read
      else
        script_name = argv.shift
        options[:script_name] = script_name
        options[:progname] = script_name
        options[:source] = File.read(script_name)
      end
    end

    if options[:progname]
      if options[:switch_parsing]
        options[:global_variables] = {}
        while (arg = argv.first)&.start_with?('-')
          val = true
          if arg.include?('=')
            arg, val = arg.split('=')
          end
          arg = arg[1..].tr('-', '_')
          options[:global_variables][arg] = val
          argv.shift
        end
      end
    end

    options[:argv] ||= argv
    options
  end

  def self.run
    options = parse_options

    crunchbang_line = options[:source].each_line.find_index { |l| l =~ /\A\#\!.*ruby/ }

    if crunchbang_line
      crunchbang = options[:source].each_line.drop(crunchbang_line).first.chomp

      if crunchbang =~ /\A\#\!\s?\S+\s+(.*)\z/
        argv = $1.split(/\s/)
        options = parse_options(argv + ['--'] + options[:argv], options)
      end
    end

    if options[:strip_before_crunchbang]
      if !crunchbang_line
        raise LoadError, "no Ruby script found in input"
      end

      options[:source] = options[:source].each_line.drop(crunchbang_line).join($/)
    end

    Core.init

    parser = Parser.new(options[:source], options[:script_name])
    node = parser.parse
    if __grb_debug__?
      pp node
      puts '-----'
    end

    iseq = Iseq.new('<main>', :main)
    Compiler.new(iseq).compile_node(node)

    vm = VM.new(Core.rb_vm_top_self, options)
    Core.prog_init(vm, options)

    vm.running = true
    vm.execute_main(iseq)
  end
end

require 'garnet_ruby/version'

require 'garnet_ruby/core/ruby'
require 'garnet_ruby/core/basic'
require 'garnet_ruby/core/object'
require 'garnet_ruby/core/class'
require 'garnet_ruby/core/primitive'
require 'garnet_ruby/core/vm_eval'
require 'garnet_ruby/core/eval'
require 'garnet_ruby/core/error'
require 'garnet_ruby/core/numeric'
require 'garnet_ruby/core/math'
require 'garnet_ruby/core/enum'
require 'garnet_ruby/core/enumerator'
require 'garnet_ruby/core/comparable'
require 'garnet_ruby/core/range'
require 'garnet_ruby/core/symbol'
require 'garnet_ruby/core/string'
require 'garnet_ruby/core/encoding'
require 'garnet_ruby/core/array'
require 'garnet_ruby/core/hash'
require 'garnet_ruby/core/regexp'
require 'garnet_ruby/core/method'
require 'garnet_ruby/core/vm_method'
require 'garnet_ruby/core/block'
require 'garnet_ruby/core/proc'
require 'garnet_ruby/core/io'
require 'garnet_ruby/core/file'
require 'garnet_ruby/core/dir'
require 'garnet_ruby/core/signal'
require 'garnet_ruby/core/process'
require 'garnet_ruby/core/marshal'
require 'garnet_ruby/core/struct'
require 'garnet_ruby/core/load'
require 'garnet_ruby/core/version'
require 'garnet_ruby/core/thread'
require 'garnet_ruby/core/time'
require 'garnet_ruby/core/vm'
require 'garnet_ruby/core/iseq'
require 'garnet_ruby/core/transcode'
require 'garnet_ruby/core/core'

require 'garnet_ruby/compiler/parser'
require 'garnet_ruby/compiler/instruction'
require 'garnet_ruby/compiler/iseq'
require 'garnet_ruby/compiler/compiler'

require 'garnet_ruby/vm/environment'
require 'garnet_ruby/vm/control_frame'
require 'garnet_ruby/vm/garnet_throw'
require 'garnet_ruby/vm/vm'
