require 'rubygems'
require 'benchmark'
require 'drb'
require 'spec'
require 'spec/runner/formatter/base_text_formatter'

module Spec
  module Runner
    module Formatter
      class BaseTextFormatter
        def dump_failure(counter, failure)
          output = @options.error_stream
          output.puts
          output.puts "#{counter.to_s})"
          output.puts colourise("#{failure.header}\n#{failure.exception.message}", failure)
          output.puts format_backtrace(failure.exception.backtrace)
          output.flush
        end
      end
    end
  end
end

class Merb::Counter
  include DRb::DRbUndumped

  attr_accessor :time
  def initialize
    @examples, @failures, @errors, @pending, @total_time = 0, 0, 0, 0, 0
    @err = ""
    @mutex = Mutex.new
  end
  
  def add(spec, out, err)
    @mutex.synchronize do
      puts
      puts "Running #{spec}."
      STDOUT.puts out
      STDOUT.flush
      match = out.match(/(\d+) examples?, (\d+) failures?(?:, (\d+) errors?)?(?:, (\d+) pending?)?/m)
      time = out.match(/Finished in (\d+\.\d+) seconds/)
      @total_time += time[1].to_f
      if match
        e, f, errors, pending = match[1..-1]
        @examples += e.to_i
        @failures += f.to_i
        @errors += errors.to_i
        @pending += pending.to_i
      end
      unless err.chomp.empty?
        @err << err.chomp << "\n"
      end
    end
  end

  def report
    puts @err
    puts
    if @failures != 0 || @errors != 0
      print "\e[31m" # Red
    elsif @pending != 0
      print "\e[33m" # Yellow
    else
      print "\e[32m" # Green
    end
    puts "Total actual time: #{@total_time}"
    puts "#{@examples} examples, #{@failures} failures, #{@errors} errors, #{@pending} pending, #{sprintf("suite run in %3.3f seconds", @time.real)}"
    # TODO: we need to report pending examples all together
    print "\e[0m"    
  end  
end

# Runs specs in all files matching the file pattern.
#
# ==== Parameters
# globs<String, Array[String]>:: File patterns to look for.
# spec_cmd<~to_s>:: The spec command. Defaults to "spec".
# run_opts<String>:: Options to pass to spec commands, for instance,
#                    if you want to use profiling formatter.
# except<Array[String]>:: File paths to skip.
def run_specs(globs, spec_cmd='spec', run_opts = "-c", except = [])
  require "optparse"
  require "spec"
  globs = globs.is_a?(Array) ? globs : [globs]
  
  counter = Merb::Counter.new
  forks = 0

  time = Benchmark.measure do
    pid = nil
    globs.each do |glob|
      Dir[glob].each do |spec|
        drb_uri = DRb.start_service(nil, counter).uri
        Kernel.fork do
          $VERBOSE = nil
          DRb.stop_service
          DRb.start_service
          counter_client = DRbObject.new_with_uri(drb_uri)
          err, out = StringIO.new, StringIO.new
          def out.tty?() true end
          options = Spec::Runner::OptionParser.parse(%W(#{spec} -fs --color), err, out)
          options.filename_pattern = File.expand_path(spec)
          Spec::Runner::CommandLine.run(options)
          begin
            counter_client.add(spec, out.string, err.string)
          rescue DRb::DRbConnError => e
            puts "#{Process.pid}: Exception caught"
            puts "#{e.class}: #{e.message}"
            retry
          end
          exit
        end
      end
      Process.waitall
    end
  end
  
  counter.time = time
  counter.report
end
