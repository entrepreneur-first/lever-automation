# frozen_string_literal: true

require_relative '../controller/controller'

class Router
  
  COMMANDS = {
    'summarise': -> {
      @controller.summarise_opportunities
    },
    'process': -> {
      @controller.process_opportunities
    },
    'process_archived': -> {
      @controller.process_opportunities(true)
    },
    'process_all': -> {
      @controller.process_opportunities(nil)
    },
    'fix tags': -> {
      @controller.fix_auto_assigned_tags
    },
    'fix links': -> {
      @controller.fix_checksum_links
    },
    'check links': -> {
      @controller.check_links
    },
    'tidy bot notes': -> {
      @controller.tidy_bot_notes
    },
    'archive accident': -> {
      @controller.archive_accidental_postings
    },
    'fix archived stage': -> {
      @controller.fix_archived_stage
    },
    'export bigquery': -> {
      puts @controller.export_to_bigquery(nil, false)
    },
    'export csv': -> {
      puts @controller.export_to_csv(nil, false)
    },
    'export csv test': -> {
      puts @controller.export_to_csv(nil, true, true)
    },
    'export csv all fields': -> {
      puts @controller.export_to_csv(nil, true)
    },
    'export csv v1': -> {
      puts @controller.export_to_csv_v1
    },
    'export webhook': -> {
      @controller.export_via_webhook(nil)
    },
    'help': -> {
      puts "\nCommands:"
      COMMANDS.keys.sort.each {|c| puts "- #{c}"}
      puts "\nCommands for specific candidates (usage: <command> {<email> or <opportunity_id>}):"
      OPPORTUNITY_COMMANDS.keys.sort.each {|c| puts "- #{c}"}
    }
  }
  
  OPPORTUNITY_COMMANDS = {
    # views
    'view': -> (opp) {
      puts JSON.pretty_generate(Util.opp_view_data(opp))
    },
    'view_csv': -> (opp) {
      puts JSON.pretty_generate(Util.flatten_hash(Util.opp_view_data(opp)))
    },
    'csv_headers': -> (opp) {
      puts JSON.pretty_generate(Util.flatten_hash(Util.opp_view_data(opp)).keys)
    },
    'feedback': -> (opp) {
      puts JSON.pretty_generate(@controller.client.feedback_for_opp(opp))
    },
    'notes': -> (opp) {
      puts JSON.pretty_generate(@controller.client.get_paged_result("#{API_URL}opportunities/#{opp['id']}/notes", {}, 'notes'))
    },
    'age': -> (opp) {
      puts "#{opp['id']}: #{opp['lastInteractionAt'] - opp['createdAt']}"
    },
    'test_rules': -> (opp) {
      @controller.test_rules(opp)
    },
    # actions
    'send_webhooks': -> (opp) {
      @controller.log.log_prefix(opp['id'] + ': ')
      @controller.send_webhooks(opp)
      @controller.log.pop_log_prefix
    },
    'bigquery': -> (opp) {
      @controller.log.log_prefix(opp['id'] + ': ')
      @controller.update_bigquery(opp)
      @controller.log.pop_log_prefix
    },
    'tidy_bot_notes': -> (opp) {
      @controller.tidy_opp_bot_notes(opp)
    },
    'process': -> (opp) {
      @controller.process_opportunity(opp)
    }
  }

  def self.interactive_prompt_str
    "Enter command, or 'help' for menu:\n(Common commands: 'export csv', 'summarise', or '[view|feedback] <email>|<opportunity_id>' to view/process one candidate)"
  end

  def self.interactive?
    (ENV['LOG_FILE'] == '1') || (ENV['CONSOLE_ASYNC'] == '0')
  end

  def self.route(command)  
    return if command == ''
    finished_successfully = false
      
    @controller = Controller.new
    @controller.log.verbose
    @controller.log.log('Command: ' + command) unless self.interactive?

    if COMMANDS.has_key?(command.to_sym)
      COMMANDS[command.to_sym].call
    else
      key = command.gsub('mailto:', '')
      command, key = key.split(' ') if key.include?(' ')
      key = (key.match(/https:\/\/hire.lever.co\/candidates\/([^\/?]+)/) || [])[1] || key

      if key.include? '@'
        # email
        os = @controller.client.opportunities_for_contact(key)
      else
        # opportunity ID
        os = [@controller.client.get_opportunity(key, {expand: @controller.client.OPP_EXPAND_VALUES})].reject{|o| o.nil?}
      end

      puts "\n" if self.interactive?

      os.each { |opp| 
        if OPPORTUNITY_COMMANDS.has_key?(command.to_sym)
          OPPORTUNITY_COMMANDS[command.to_sym].call(opp)
        else
          OPPORTUNITY_COMMANDS[:process].call(opp)
        end
      }
    end
    
    finished_successfully = true
    
    ensure
      puts "\n" if self.interactive?
      @controller.log.log("#{finished_successfully ? 'Finished' : 'Aborted'} command: " + command)
  end

end
