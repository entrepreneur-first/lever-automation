require 'daemons'

require_relative 'client'
client = Client.new(ENV['LKEY'])

Daemons.run_proc('lever_daemon.rb') do
  loop do
    client.process_opportunities
    sleep(10)
  end
end