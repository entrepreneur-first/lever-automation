# frozen_string_literal: true

require_relative 'app/worker'
require_relative 'app/router'

loop do
  puts "\nEnter 'summarise', 'process', 'fix tags', 'check links', or '[view|feedback] <email>|<opportunity_id>' to view/process one candidate:"
  command = gets.chomp

  case command
  when ''
      break

  else
    if command.start_with?('i ')
      Router.route(command.delete_prefix('i ')
    else
      Worker::perform_async(command)
    end
  end
end

puts 'OK, bye'
