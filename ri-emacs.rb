#!/usr/bin/env ruby
## ri-emacs.rb helper script for use with ri-ruby.el
#
# Modified by Perry Smith <pedz@easesoftware.com>
#   July 11th, 2009 -- and other dates.
#
#   Added debugging facilities as well as making it work with Ruby 1.9
#   on a Mac OS X system running 10.5.  In particular, the tty must
#   be set up properly.
#
#
# Author: Kristof Bastiaensen <kristof@vleeuwen.org>
#
#
#    Copyright (C) 2004,2006 Kristof Bastiaensen
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
#----------------------------------------------------------------------
#
#  For information on how to use and install see ri-ruby.el
#
require 'logger'

def logger
  if @logger.nil?
    @logger = Logger.new("/tmp/ri-emacs-" + ENV["USER"])
    # @logger.level = Logger::DEBUG
    @logger.level = Logger::INFO
  end
  @logger
end

logger.debug("ri-emacs started #{Time.now} running version #{RUBY_VERSION}")

begin
  # RDoc 2
  require 'rubygems'
  require 'rdoc/ri'
  require 'rdoc/ri/paths'
  require 'rdoc/ri/writer'
  require 'rdoc/ri/cache'
  require 'rdoc/ri/util'
  require 'rdoc/ri/reader'
  require 'rdoc/ri/formatter'
  require 'rdoc/ri/display'
  logger.debug("RDoc 2 loaded")
rescue LoadError
  # RDoc 1
  require 'rdoc/ri/ri_paths'
  require 'rdoc/ri/ri_cache'
  require 'rdoc/ri/ri_util'
  require 'rdoc/ri/ri_reader'
  require 'rdoc/ri/ri_formatter'
  require 'rdoc/ri/ri_display'
  logger.debug("RDoc 1 loaded")
end

class DefaultDisplay
  def full_params(method)
    method.params.split(/\n/).each do |p|
      p.sub!(/^#{method.name}\(/o,'(')
      unless p =~ /\b\.\b/
        p = method.full_name + p
      end
      @formatter.wrap(p)
      @formatter.break_to_newline
    end
  end
end

def debug(*args)
  if DEBUG_ON
    open_debug.puts *args
    open_debug.flush
  end
end

def open_debug
  $debug ||= Kernel.open("/tmp/ri-emacs-" + ENV["USER"], "a")
end

def output(arg)
  arg = "nil" if arg.nil?
  logger.debug("Wrote: #{arg}")
  $stdout.puts arg
  $stdout.flush
end

def ruby_minimum_version?(*version)
  RUBY_VERSION.split(".").
    map{ |i| i.to_i }.
    <=>(version) > -1
end

class RiEmacs
  include RDoc
  Options = Struct.new(:formatter, :use_stdout, :width)

  def initialize(paths)
    if ruby_minimum_version?(1, 8, 5)
      begin
        require 'rubygems'
        Dir["#{Gem.path}/doc/*/ri"].each do |path|
          RI::Paths::PATH << path
        end
      rescue LoadError => e
        logger.error(e.to_s)
      end
    end

    paths = paths || RI::Paths.path(true, true, true, true)

    @ri_reader = RI::Reader.new(RI::Cache.new(paths))
    @display = RI::Display.new(RI::Formatter.for("ansi"), 72, true)
  end

  def lookup_keyw(keyw)
    begin
      desc = RI::NameDescriptor.new(keyw)
    rescue => e
      logger.error(e.to_s)
      return nil
    end

    last_space = @ri_reader.top_level_namespace
    class_name = nil
    container = desc.class_names.inject(last_space) do
      |container, temp_class_name|
      class_name = temp_class_name
      last_space = @ri_reader.lookup_namespace_in(temp_class_name, container)
      last_space.find_all {|m| m.name == temp_class_name}
    end

    if desc.method_name.nil?
      if [?., ?:, ?#].include? keyw[-1]
        namespaces = @ri_reader.lookup_namespace_in("", container)
        is_class_method = case keyw[-1]
                          when ?. then nil
                          when ?: then true
                          when ?# then false
                          end
        methods = @ri_reader.find_methods("", is_class_method, container)
        return nil if methods.empty? && namespaces.empty?
      else
        #class_name = desc.class_names.last
        logger.debug("class_name is '#{class_name}'")
        return nil if class_name.nil?
        namespaces = last_space.find_all { |n| n.name.index(class_name).zero? }
        return nil if namespaces.empty?
        methods = []
      end
    else
      return nil if container.empty?
      namespaces = []
      methods = @ri_reader.
        find_methods(desc.method_name,
                     desc.is_class_method,
                     container).
        find_all { |m| m.name.index(desc.method_name).zero? }
      return nil if methods.empty?
    end

    return desc, methods, namespaces
  end

  def completion_list(keyw)
    return @ri_reader.full_class_names if keyw == ""

    desc, methods, namespaces = lookup_keyw(keyw)
    return nil unless desc

    if desc.class_names.empty?
      return methods.map { |m| m.name }.uniq
    else
      return methods.map { |m| m.full_name } +
        namespaces.map { |n| n.full_name }
    end
  end

  def complete(keyw, type)
    list = completion_list(keyw)

    if list.nil?
      return "nil"
    elsif type == :all
      return "(" + list.map { |w| w.inspect }.join(" ") + ")"
    elsif type == :lambda
      if list.find { |n|
          n.split(/(::)|#|\./) == keyw.split(/(::)|#|\./) }
        return "t"
      else
        return "nil"
      end
      # type == try
    elsif list.size == 1 and
        list[0].split(/(::)|#|\./) == keyw.split(/(::)|#|\./)
      return "t"
    end

    first = list.shift;
    if first =~ /(.*)((?:::)|(?:#))(.*)/
      other = $1 + ($2 == "::" ? "#" : "::") + $3
    end

    len = first.size
    match_both = false
    list.each do |w|
      while w[0, len] != first[0, len]
        if other and w[0, len] == other[0, len]
          match_both = true
          break
        end
        len -= 1
      end
    end

    if match_both
      return other.sub(/(.*)((?:::)|(?:#))/) {
        $1 + "." }[0, len].inspect
    else
      return first[0, len].inspect
    end
  end

  def display_info(keyw)
    desc, methods, namespaces = lookup_keyw(keyw)
    return false if desc.nil?

    logger.debug("desc is #{desc.inspect}")
    if desc.method_name
      methods = methods.find_all { |m| m.name == desc.method_name }
      return false if methods.empty?
      meth = @ri_reader.get_method(methods[0])
      logger.debug("meth is #{meth.inspect}")
      @display.display_method_info(meth)
    else
      namespaces = namespaces.find_all { |n| n.full_name == desc.full_class_name }
      return false if namespaces.empty?
      klass = @ri_reader.get_class(namespaces[0])
      logger.debug("klass is #{klass.inspect}")
      @display.display_class_info(klass)
    end

    return true
  end

  def display_args(keyw)
    desc, methods, namespaces = lookup_keyw(keyw)
    return nil unless desc && desc.class_names.empty?

    methods = methods.find_all { |m| m.name == desc.method_name }
    return false if methods.empty?
    methods.each do |m|
      meth = @ri_reader.get_method(m)
      @display.full_params(meth)
    end

    return true
  end

  # return a list of classes for the method keyw
  # return nil if keyw has already a class
  def class_list(keyw, rep='\1')
    desc, methods, namespaces = lookup_keyw(keyw)
    return nil unless desc && desc.class_names.empty?

    methods = methods.find_all { |m| m.name == desc.method_name }

    return "(" + methods.map do |m|
      "(" + m.full_name.sub(/(.*)(#|(::)).*/,
                            rep).inspect + ")"
    end.uniq.join(" ") + ")"
  end

  # flag means (#|::)
  # return a list of classes and flag for the method keyw
  # return nil if keyw has already a class
  def class_list_with_flag(keyw)
    class_list(keyw, '\1\2')
  end
end

class Command
  def initialize(ri)
    @ri = ri
  end

  Command2Method = {
    "TRY_COMPLETION" => :try_completion,
    "COMPLETE_ALL" => :complete_all,
    "LAMBDA" => :lambda,
    "CLASS_LIST" => :class_list,
    "CLASS_LIST_WITH_FLAG" => :class_list_with_flag,
    "DISPLAY_ARGS" => :display_args,
    "DISPLAY_INFO" => :display_info}

  def read_next
    if (line = STDIN.gets).nil?
      logger.debug("Empty line -- exiting")
      return nil
    end
    logger.debug("read: #{line.chomp}")
    cmd, param = /(\w+)(.*)$/.match(line)[1..2]
    method = Command2Method[cmd]
    fail "unrecognised command: #{cmd}" if method.nil?
    send(method, param.strip)
    return true
  end

  def try_completion(keyw)
    output @ri.complete(keyw, :try)
  end

  def complete_all(keyw)
    output @ri.complete(keyw, :all)
  end

  def lambda(keyw)
    output @ri.complete(keyw, :lambda)
  end

  def class_list(keyw)
    output @ri.class_list(keyw)
  end

  def class_list_with_flag(keyw)
    output @ri.class_list_with_flag(keyw)
  end

  def display_args(keyw)
    @ri.display_args(keyw)
    output "RI_EMACS_END_OF_INFO"
  end

  def display_info(keyw)
    logger.debug("@ri is class #{@ri.class}")
    ret = @ri.display_info(keyw)
    logger.debug("@ri.display returned #{ret.inspect}")
    output "RI_EMACS_END_OF_INFO"
  end

  def test
    [:try, :all, :lambda].each do |t|
      @ri.complete("each", t) or
        fail "@ri.complete(\"each\", #{t.inspect}) returned nil"
    end
    @ri.display_info("Array#each") or
      raise 'display_info("Array#each") returned false'
  end
end

arg = ARGV[0]

if arg == "--test"
  cmd = Command.new(RiEmacs.new(nil))
  cmd.test
  puts "Test succeeded"
else
  begin
    if STDIN.isatty
      logger.debug "Turning off echo"
      system("stty -echo -opost")
    end
    logger.debug("$stdout = #{$stdout.inspect}")
    cmd = Command.new(RiEmacs.new(arg))
    output 'READY'
    loop do
      break if cmd.read_next.nil?
    end
  rescue => e
    logger.fatal(e.to_s + "\n" + e.backtrace.join("\n"))
  ensure
    if STDIN.isatty
      logger.debug "Turning echo back on"
      system("stty echo opost")
    end
  end
end
