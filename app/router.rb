# frozen_string_literal: true

require_relative '../controller/controller'

class Router
  
  COMMANDS = {
    # help
    'help': -> {
      puts "\nCommands:"
      COMMANDS.keys.sort.each {|c| puts "- #{c}"}
      puts "\nCommands for specific candidates (usage: <command> {<email> or <opportunity_id>}):"
      OPPORTUNITY_COMMANDS.keys.sort.each {|c| puts "- #{c}"}
    },
    
    # fixes
    'archive accident': -> {
      @controller.archive_accidental_postings
    },
    'fix archived stage': -> {
      @controller.fix_archived_stage
    },
    'fix links': -> {
      @controller.fix_checksum_links
    },
    'fix tags': -> {
      @controller.fix_auto_assigned_tags
    },
    'tidy bot notes': -> {
      @controller.tidy_bot_notes
    },
    'tidy_bot_notes': -> (opp) {
      @controller.tidy_opp_bot_notes(opp)
    },
    
    # checks
    'check links': -> {
      @controller.check_links
    },
    
    # export
    'export bigquery': -> {
      puts @controller.export_to_bigquery(nil, false)
    },
    'bigquery': -> (opp) {
      @controller.log.log_prefix(opp['id'] + ': ')
      @controller.update_bigquery(opp)
      @controller.log.pop_log_prefix
    },
    'export csv': -> {
      puts @controller.export_to_csv(nil, false)
    },
    'test export csv': -> {
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

    # import    
    'import bigquery': -> (param_str) {
      @controller.import_from_bigquery(param_str)
    },
    'test import bigquery': -> (param_str) {
      @controller.import_from_bigquery(param_str, true)
    },
    
    # process
    'process': -> (opp) {
      @controller.process_opportunity(opp)
    }
    'process_all': -> {
      @controller.process_opportunities(nil)
    },
    'process_archived': -> {
      @controller.process_opportunities(true)
    },
    
    # views
    'summarise': -> {
      @controller.summarise_opportunities
    },
    'view': -> (opp) {
      puts JSON.pretty_generate(Util.opp_view_data(opp))
    },
    'view_csv': -> (opp) {
      puts JSON.pretty_generate(Util.view_flat(opp))
    },
    'csv_headers': -> (opp) {
      puts JSON.pretty_generate(Util.view_flat(opp).keys)
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
    'view user': -> (search) {
      users = @controller.client.users
      if search.include?('@')
        result = Util.lookup_row_fuzzy(users, search, 'email')
      elsif search.include(' ')
        result = Util.lookup_row_fuzzy(users, search, 'name')
      else
        result = Util.lookup_row(users, search)
      end
      puts JSON.pretty_generate(result)
    },
    'view posting': -> (search) {
      postings = @controller.client.postings
      if search.include(' ')
        result = Util.lookup_row_fuzzy(postings, search, 'name')
      else
        result = Util.lookup_row(postings, search)
      end
      puts JSON.pretty_generate(result)
    },
    
    # actions
    'send_webhooks': -> (opp) {
      @controller.log.log_prefix(opp['id'] + ': ')
      @controller.send_webhooks(opp)
      @controller.log.pop_log_prefix
    },

    # functionality tests
    'slack': -> (param_str) {
      puts JSON.pretty_generate(@controller.slack_lookup({'text' => param_str, 'command' => 'lever'}))
    },    
    'test_rules': -> (opp) {
      @controller.test_rules(opp)
    },
    'add_coffee_feedback_test': -> (opp) {
      @controller.add_coffee_feedback(opp, {})
    },
  }
  
  def self.interactive_prompt_str
    "Enter command, or 'help' for menu:\n(Common commands: 'export bigquery', 'summarise', or '[view|feedback] <email>|<opportunity_id>' to view/process one candidate)"
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

    command_func = nil
    COMMANDS.each {|text, func|
      if command.start_with?(text.to_s)
        command_func = {text: text.to_s, func: func}
        break
      end
    }

    param_str = command.delete_prefix(command_func[:text]).strip
    
    if command_func.nil? || command_func[:func].parameters.fetch(0, []).fetch(1, nil) == :opp
      param_str.gsub!('mailto:', '')
      param_str = (param_str.match(/https:\/\/hire.lever.co\/candidates\/([^\/?]+)/) || [])[1] || param_str

      if param_str.include? '@'
        # email
        os = @controller.client.opportunities_for_contact(param_str)
      else
        # opportunity ID
        os = [@controller.client.get_opportunity(param_str, {
            expand: @controller.client.OPP_EXPAND_VALUES
          })].reject{|o| o.nil?}
      end

      puts "\n" if self.interactive?

      os.each { |opp|
        unless command_func.nil?
          command_func[:func].call(opp)
        else
          COMMANDS[:process].call(opp)
        end
      }
      
    elsif command_func[:func].arity == 0
      command_func[:func].call()
      
    else
      command_func[:func].call(param_str)
    end

    finished_successfully = true
    
    ensure
      puts "\n" if self.interactive?
      @controller.log.log("#{finished_successfully ? 'Finished' : 'Aborted'} command: " + command)
  end

end
