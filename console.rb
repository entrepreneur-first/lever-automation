# frozen_string_literal: true

require_relative 'app/worker'
require_relative 'app/router'

loop do
  puts "\n" + Router.interactive_prompt_str
  command = gets.chomp
  break if command == ''

  if command.start_with?('i ') || ((ENV['CONSOLE_ASYNC'] == '0') && !command.start_with?('a ') && !command.start_with?('async '))
    # perform interactively
    Router.route(command.delete_prefix('i '))
  else
    command = command.delete_prefix('a ').delete_prefix('async ')
    # perform via worker
    # -> so we don't die on dropped client connection, record logs, etc
    puts "Sending command to async worker queue: " + command
    Worker::perform_async(command)
  end
end

puts 'OK, bye'
