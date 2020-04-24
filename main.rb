# frozen_string_literal: true

require_relative 'app/controller'
controller = Controller.new

loop do
  puts "\nEnter 'summarise', 'process', 'fix tags', 'check links', or '[view|feedback] <email>' to view/process one candidate:"
  command = gets.chomp

  case command
  when ''
      break
      
  when 'summarise'
      controller.summarise_opportunities
      
  when 'process'
      controller.process_opportunities
      
  when 'fix tags'
      controller.fix_auto_assigned_tags
  
  when 'fix links'
      controller.fix_checksum_links
  
  when 'check links'
      controller.check_links

  else
    command = command.gsub('mailto:', '')
    command, email = command.split(' ') if command.include?(' ')
    os = controller.client.opportunities_for_contact(email)
    case command
    when 'view'
      puts JSON.pretty_generate(os)
    when 'feedback'
      os.each{ |opp| puts JSON.pretty_generate controller.client.feedback_for_opp(opp) }
    else
      os.each { |opp| controller.process_opportunity(opp) }
    end
  end
end

puts 'OK, bye'
