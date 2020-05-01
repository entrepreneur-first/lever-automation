# frozen_string_literal: true

require_relative 'app/worker'
require_relative 'app/router'

loop do
  puts "\n" + Router.interactive_prompt_str
  command = gets.chomp
  break if command == ''

  if command.start_with?('i ')
    # perform interactively
    Router.route(command.delete_prefix('i ')
  else
    # perform via worker
    # -> so we don't die on dropped client connection, record logs, etc
    Worker::perform_async(command)
  end
end

puts 'OK, bye'
