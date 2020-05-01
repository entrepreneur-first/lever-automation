# frozen_string_literal: true

require 'daemons'
require_relative 'app/controller'

controller = Controller.new

Daemons.run_proc('lever_daemon.rb') do
  loop do
    controller.process_opportunities unless ENV['ENABLE_DAEMON'].nil? || ENV['ENABLE_DAEMON'].empty? || ['0', 'false'].include?(ENV['ENABLE_DAEMON'].downcase)
    break if controller.terminating?
    sleep(10)
  end
end
