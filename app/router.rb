# frozen_string_literal: true

require_relative 'controller'

class Router

  def self.interactive_prompt_str
    "Enter 'summarise', 'process', 'fix tags', 'check links', or '[view|feedback] <email>|<opportunity_id>' to view/process one candidate:"
  end

  def self.interactive?
    (ENV['LOG_FILE'] == '1') || (ENV['CONSOLE_ASYNC'] == '0')
  end

  def self.route(command)  
    return if command == ''
    finished_successfully = false
      
    controller = Controller.new
    controller.log.verbose
    
    controller.log.log('Command: ' + command) unless self.interactive?

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

    when 'archive accident'
      controller.archive_accidental_postings

    else
      key = command.gsub('mailto:', '')
      command, key = key.split(' ') if key.include?(' ')
      key = (key.match(/https:\/\/hire.lever.co\/candidates\/([^\/?]+)/) || [])[1] || key

      if key.include? '@'
        # email
        os = controller.client.opportunities_for_contact(key)
      else
        # opportunity ID
        os = [controller.client.get_opportunity(key, {expand: controller.client.OPP_EXPAND_VALUES})].reject{|o| o.nil?}
      end

      puts "\n" if self.interactive?

      case command
      when 'view'
        puts JSON.pretty_generate(os)
      when 'feedback'
        os.each{ |opp| puts JSON.pretty_generate controller.client.feedback_for_opp(opp) }
      when 'notes'
        os.each{ |opp| puts JSON.pretty_generate controller.client.get_paged_result("#{API_URL}opportunities/#{opp['id']}/notes", {}, 'notes') }
      when 'tidy_bot_notes'
        os.each{ |opp| controller.tidy_opp_bot_notes(opp) }
      when 'age'
        os.each{ |opp| puts "#{opp['id']}: #{opp['lastInteractionAt'] - opp['createdAt']}" }
      else
        os.each{ |opp| controller.process_opportunity(opp) }
      end
    end
    
    finished_successfully = true
    
    ensure
      puts "\n" if self.interactive?
      controller.log.log("#{finished_successfully ? 'Finished' : 'Aborted'} command: " + command)
  end

end
