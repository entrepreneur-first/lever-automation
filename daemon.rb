# frozen_string_literal: true

require 'daemons'
require_relative 'app/controller'

controller = Controller.new

Daemons.run_proc('lever_daemon.rb') do
  loop do
    controller.process_opportunities
    sleep(10)
  end
end
