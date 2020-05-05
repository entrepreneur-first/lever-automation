# frozen_string_literal: true

require 'method_source'
require_relative '../config/config'
require_relative '../app/util'
require_relative '../app/log'
require_relative '../app/client'
require_relative '../config/rules'

class BaseController

  def initialize
    @log = Log.new
    @client = Client.new(ENV['LKEY'], @log)
    @rules = Rules.new(@client)
    
    @terminating = false
    trap('TERM') do
      @terminating = true
    end
  end
  
  def client
    @client
  end
  
  def log
    @log
  end
  
  def rules
    @rules
  end
  
  def terminating?
    log.log('Received SIGTERM') if @terminating
    @terminating
  end

  def exit_on_sigterm
    raise "SIGTERM: Gracefully aborting job" if terminating?
  end

end
