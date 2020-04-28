# frozen_string_literal: true

require_relative 'app/controller'
controller = Controller.new
controller.log.verbose

loop do
  puts "\nEnter 'summarise', 'process', 'fix tags', 'check links', or '[view|feedback] <email>|<opportunity_id>' to view/process one candidate:"
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
    email = command.gsub('mailto:', '')
    command, email = email.split(' ') if email.include?(' ')
    email = (email.match(/https:\/\/hire.lever.co\/candidates\/([^?]+)/) || [])[1] || email

    if email.include? '@'
      os = controller.client.opportunities_for_contact(email)
    else
      os = [controller.client.get_opportunity(email, {expand: controller.client.OPP_EXPAND_VALUES})]
    end

    case command
    when 'view'
      puts JSON.pretty_generate(os)
    when 'feedback'
      os.each{ |opp| puts JSON.pretty_generate controller.client.feedback_for_opp(opp) }
    when 'notes'
      os.each{ |opp| puts JSON.pretty_generate controller.client.get_paged_result("#{API_URL}opportunities/#{opp['id']}/notes", {}, 'notes') }
    else
      os.each { |opp| controller.process_opportunity(opp) }
    end
  end
end

puts 'OK, bye'
