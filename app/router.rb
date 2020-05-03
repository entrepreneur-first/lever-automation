# frozen_string_literal: true

require_relative 'controller'

class Router

  def self.interactive_prompt_str
    "Enter 'summarise', 'process', 'fix tags', 'check links', or '[view|feedback] <email>|<opportunity_id>' to view/process one candidate:"
  end

  def self.route(command)  
    return if command == ''
  
    controller = Controller.new
    controller.log.verbose
    
    controller.log.log('Command: ' + command)

    case command
    when 'summarise'
      controller.summarise_opportunities
        
    when 'process'
      controller.process_opportunities

    when 'process_archived'
      controller.process_opportunities(true)
        
    when 'process_all'
      controller.process_opportunities(nil)
        
    when 'fix tags'
      controller.fix_auto_assigned_tags
    
    when 'fix links'
      controller.fix_checksum_links
    
    when 'check links'
      controller.check_links
        
    when 'tidy bot notes'
      controller.tidy_bot_notes

    else
      key = command.gsub('mailto:', '')
      command, key = email.split(' ') if key.include?(' ')
      key = (key.match(/https:\/\/hire.lever.co\/candidates\/([^?]+)/) || [])[1] || key

      if key.include? '@'
        # email
        os = controller.client.opportunities_for_contact(key)
      else
        # opportunity ID
        os = [controller.client.get_opportunity(key, {expand: controller.client.OPP_EXPAND_VALUES})]
      end

      case command
      when 'view'
        puts JSON.pretty_generate(os)
      when 'feedback'
        os.each{ |opp| puts JSON.pretty_generate controller.client.feedback_for_opp(opp) }
      when 'notes'
        os.each{ |opp| puts JSON.pretty_generate controller.client.get_paged_result("#{API_URL}opportunities/#{opp['id']}/notes", {}, 'notes') }
      when 'tidy_bot_notes'
        os.each{ |opp| controller.tidy_opp_bot_notes(opp) }
      else
        os.each { |opp| controller.process_opportunity(opp) }
      end
    end
    
    controller.log.log('Finished command: ' + command)
  end

end
