# frozen_string_literal: true

require 'logger'

LOG_FILE = 'logs/' + Time.now().strftime('%Y-%m-%d') + '.log'
ERROR_LOG_FILE = 'logs/' + Time.now().strftime('%Y-%m-%d') + '_error.log'

class Log

  def initialize
    @log_verbose = false
    @log_prefix = []
    
    @log = Logger.new(ENV['LOG_FILE'].nil? ? STDOUT : LOG_FILE)
    @error_log = Logger.new(ENV['LOG_FILE'].nil? ? STDOUT : ERROR_LOG_FILE)

    @log.formatter = @error_log.formatter = proc { |severity, datetime, progname, msg| ENV['LOG_FILE'].nil? ? "#{msg}\n" : "#{severity}, #{datetime}, #{msg}\n" }
  end

  def log(msg)
    msg = log_prefix_lines(msg)
    puts msg unless ENV['LOG_FILE'].nil?
    @log.info(msg)
  end

  def warn(msg)
    msg = msg
    puts log_prefix_lines("WARN: " + msg) unless ENV['LOG_FILE'].nil?
    @log.warn(log_prefix_lines(msg))
  end

  def error(msg)
    msg = msg
    puts log_prefix_lines("ERROR: " + msg) unless ENV['LOG_FILE'].nil?
    @log.error(log_prefix_lines(msg))
    @error_log.error(log_prefix_lines(msg))
  end

  def log_prefix(p=nil)
    @log_prefix << p unless p.nil?
    @log_prefix.join
  end

  def pop_log_prefix
    @log_prefix.pop
  end
  
  def log_prefix_lines(msg)
    log_prefix + msg.gsub("\n", "\n" + log_prefix + '  ')
  end

end