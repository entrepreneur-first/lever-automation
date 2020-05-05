# frozen_string_literal: true

module Controller_Fixes

  # temp commands

  # detect duplicate opportunities for a candidate
  def detect_duplicate_opportunities(opp)
    client.remove_tags_with_prefix(opp, TAG_DUPLICATE_OPPS_PREFIX) if opp["applications"].count < 2
    posting_ids = opp["applications"].map {|a| a["posting"] || 'none'}
    duplicates = Util.dup_hash(posting_ids)
    # multiple opps, same position
    client.add_tag(opp, TAG_DUPLICATE_OPPS_PREFIX + " same posting") if duplicates.length > 0
    # multiple opps, for different positions
    client.add_tag(opp, TAG_DUPLICATE_OPPS_PREFIX + " different posting") if posting_ids.reject {|p| p == 'none' }.uniq.length > 1
    # one or more opps for a position, as well as a lead with no job position assigned
    client.add_tag(opp, TAG_DUPLICATE_OPPS_PREFIX + " without posting") if posting_ids.reject {|p| p == 'none' }.length > 0 && posting_ids.include?("none")
  end

  def opportunities_without_posting
    log_string = 'opportunities_without_posting'
    params = {}
    arr = []
    tags = Hash.new(0)
    result = HTTParty.get(OPPORTUNITIES_URL + Util.to_query(params), basic_auth: auth)
    result.fetch('data').each { |o|
      next if o["applications"].count > 0
      arr += [{id: o["id"], tags: o["tags"]}]
      o["tags"].each { |tag| tags[tag] += 1 }
    }
    puts "\nOpportunities: " + arr.count.to_s
    puts "\nTags:" + JSON.pretty_generate(tags)
    page = 0
    while result.fetch('hasNext')
      next_batch = result.fetch('next')
      result = api_call_log(log_string, page) do
        HTTParty.get(OPPORTUNITIES_URL + Util.to_query(params.merge(offset: next_batch)), basic_auth: auth)
      end
      result.fetch('data').each { |o|
        next if o["applications"].count > 0
        arr += [{id: o["id"], tags: o["tags"]}]
        o["tags"].each { |tag| tags[tag] += 1 }
      }
      puts "\nOpportunities: " + arr.count.to_s
      puts "\nTags:" + JSON.pretty_generate(tags)
      page += 1
    end
    {opportunities: arr, tags: tags}
  end

  def check_links
    client.process_paged_result(OPPORTUNITIES_URL, {archived: false}, 'checking for links') { |opp|
      puts JSON.pretty_generate(opp) if opp['links'].length > 1
    }
  end

  # fixes

  def fix_auto_assigned_tags
    client.process_paged_result(OPPORTUNITIES_URL, {archived: false, expand: ['applications']}, 'fixing auto-assigned tags for active opportunities') { |opp|
      next if opp['applications'].length == 0
      client.add_tags_if_unset(opp, TAG_ASSIGNED_TO_LOCATION, true) if opp['applications'][0]['user'] == LEVER_BOT_USER
      client.remove_tag(opp, TAG_SOURCE_FROM_APPLICATION_ERROR) if !Util.has_application(opp) || !Util.is_cohort_app(opp)
    }
  end

  def fix_checksum_links
    client.process_paged_result(OPPORTUNITIES_URL, {archived: false}, 'fixing checksum links for active opportunities') { |opp|
      client.remove_links_with_prefix(opp, AUTO_LINK_PREFIX + 'checksum/')
    }
  end

  def tidy_bot_notes
    client.process_paged_result(OPPORTUNITIES_URL, {archived: false}, 'bot links for active opps') { |opp|
      exit_on_sigterm
      tidy_opp_bot_notes(opp)
    }
  end
  
  def tidy_opp_bot_notes(opp)
    client.process_paged_result("#{client.opp_url(opp)}/notes", {}) { |note|
      if !note['deletedAt'].nil? && note['fields'][0]['value'].start_with?('Referred by')
        if opp['lastInteractionAt'] > (note['deletedAt'] + 60000)
          log.log('Not reinstating note due to more recent interaction: ' + opp['id'] + ':' + note['id'])
        else
          client.add_note(opp, note['fields'][0]['value'])
        end
      end

      next unless note['deletedAt'].nil?
      next if note['user'] != LEVER_BOT_USER
      
      next unless note['fields'][0]['value'].start_with?('Updated reporting') || note['fields'][0]['value'].start_with?('Assigned to ')
      client.delete("#{client.opp_url(opp)}/notes/#{note['id']}")
    }
  end
  
  def archive_accidental_postings
    # 1. get active opportunities
    i = 0
    client.process_paged_result(OPPORTUNITIES_URL, {archived: false, expand:['applications']}, 'archiving accidental postings for active opps') { |opp|
      exit_on_sigterm
      # 2. find application with user = BOT_USER_ID
      next if !Util.has_posting(opp)
      next if !Util.is_cohort_app(opp)
      # puts "cohort app: #{opp['applications'][0]}"
      next if opp['applications'][0]['user'] != LEVER_BOT_USER
      #puts "App from BOT: #{opp['id']}"
      # 3. check for most recent stage: user = BOT_USER_ID; stage != 'lead-new'
      latest_stage = opp['stageChanges'].last
      #puts latest_stage
      next if latest_stage['userId'] != LEVER_BOT_USER
      next if ['lead-new','lead-reached-out'].include?(latest_stage['toStageId'])
      next if (latest_stage['updatedAt']-opp['createdAt']).between?(-5000, 5000)
      # next if opp['stageChanges'].length == 1
      # archive
      i+=1
      #puts JSON.pretty_generate(opp)
      puts "#{opp['id']}: #{latest_stage}"
      client.add_tag(opp, '🤖 fix_unarchived_5')
    }
    puts "total: #{i}"
  end
  
  def fix_archived_stage
    from_stages = Hash.new(0)
    stages = Hash.new(0)
    users = Hash.new(0)
    i=0
    
    client.process_paged_result(OPPORTUNITIES_URL, {archived: true, expand:['applications', 'stage']}, 'fixing stage for achived candidates') { |opp|
      exit_on_sigterm
      # 2. find application with user = BOT_USER_ID
      next if !Util.has_posting(opp)
      next if !Util.is_cohort_app(opp)
      next if opp['applications'][0]['user'] != LEVER_BOT_USER
      # 3. check for most recent stage: user = BOT_USER_ID; stage != 'lead-new'
      latest_stage = opp['stageChanges'].last
      next if latest_stage['userId'] != LEVER_BOT_USER
      next if !['applicant-new'].include?(latest_stage['toStageId'])
      next if opp['stageChanges'].length < 2

      # fix stage
      prior_stage = opp['stageChanges'].last(2).first
      next if prior_stage.nil?

      from_stages[latest_stage['toStageId']] += 1
      stages[prior_stage['toStageId']] += 1
      users[prior_stage['userId']] += 1
      
      i+=1
      client.add_tag(opp, '🤖 fix_archived_stage')
      client.update_stage(opp, prior_stage['toStageId'])
    }
    puts JSON.pretty_generate(from_stages)
    puts JSON.pretty_generate(stages)
    puts JSON.pretty_generate(users)
  end

end