# frozen_string_literal: true

module Controller_ProcessUpdates

  # process a single opportunity
  # apply changes & trigger webhook as necessary
  def process_opportunity(opp)
    return {'anonymized': true} if opp['isAnonymized']
  
    result = {}
    log.log_prefix(opp['id'] + ': ')
    client.batch_updates

    # checks lastInteractionAt and tag checksum, creating checksum tag if necessary
    last_update = latest_change(opp)
    # should notify of change based on state before we executed?
    notify = last_update[:time] > last_change_detected(opp) + 100

    if check_no_posting(opp)
      # if we added to a job then reload as tags etc will have changed automagically 
      # based on new posting assignment
      client.refresh_opp(opp)
      result['assigned_to_job'] = true
    end
    
    check_linkedin_optout(opp)
    remove_legacy_attributes(opp)

    if !Util.has_posting(opp) || Util.is_cohort_app(opp)
      prepare_app_responses(opp)
      add_links(opp)
      summarise_feedbacks(opp)
      # detect_duplicate_opportunities(opp)
      rules.do_update_tags(opp)

      [tags_have_changed?(opp), links_have_changed?(opp)].each{ |update|
        unless update.nil?
          last_update = update
          notify = true
        end
      }

      if notify
        # send webhook of change
        notify_of_change(opp, last_update)
        result['sent_webhook'] = result['updated'] = true
      else 
        # we didn't have a change to notify, but we added one or more notes
        # which will update lastInteractionAt
        # so update LAST_CHANGE_TAG to avoid falsely detecting update next time
        update_changed_tag(opp, [opp['_addedNoteTimestamp'], opp['lastInteractionAt'], last_change_detected(opp)].reject{ |v|v.nil? }.max)
      end

      if commit_bot_metadata(opp)
        result['updated'] = true
      end
    end

    if client.commit_opp(opp)
      result['updated'] = true
    end

    log.pop_log_prefix
    client.batch_updates(false)
    result
  end

  def check_linkedin_optout(opp)
    # attempt to identify LinkedIn Inmail responses that have opted-out
    # we don't have a way to read the inmail responses, so instead look for opportunities
    # that haven't had an interaction since within a few seconds of creation
    # (leads appear to be created when the recipient opts in/out, and before they type their reply)
    
    # 1. look for opps with no job, stage=responded, origin=sourced, sources=LinkedIn, no interaction since 5s after creation. Otherwise ignore & remove all relevant tags.
    if !Util.has_posting(opp) && 
       [opp['stage'], opp['stage']['id']].include?('lead-responded') && 
       opp['origin'] == 'sourced' && 
       opp['sources'] == ['LinkedIn'] &&
       (opp['lastInteractionAt'] < opp['createdAt'] + 5000)
        
      if opp['emails'].length > 0 ||
         opp['phones'].length > 0
        # known opt-in since we've had an email and/or phone provided
        client.add_tags_if_unset(opp, TAG_LINKEDIN_OPTIN)
        client.remove_tags_if_set(opp, [TAG_LINKEDIN_OPTOUT, TAG_LINKEDIN_OPTIN_LIKELY])
      elsif opp['lastInteractionAt'] > opp['createdAt'] + 1500
        # hacky imperfect heuristic: ~majoritiy of opps that indicated intrested in receiving more
        # appear to have their status updated > 1.5s after creation
        client.add_tags_if_unset(opp, TAG_LINKEDIN_OPTIN_LIKELY)
        client.remove_tags_if_set(opp, [TAG_LINKEDIN_OPTIN, TAG_LINKEDIN_OPTOUT])
      else
        # majority of opps not updated since 1.5s after creation appear to be opt-outs
        client.add_tags_if_unset(opp, TAG_LINKEDIN_OPTOUT)
        client.remove_tags_if_set(opp, [TAG_LINKEDIN_OPTIN, TAG_LINKEDIN_OPTIN_LIKELY])
      end
    else
      client.remove_tags_if_set(opp, [TAG_LINKEDIN_OPTOUT, TAG_LINKEDIN_OPTIN, TAG_LINKEDIN_OPTIN_LIKELY])
    end    
  end

  # process leads not assigned to any posting
  # ~~
  # Note slight confusion between Lever interface vs API:
  # - Leads not assigned to a job posting show up in Lever as candidates with "no opportunity", but are returned in the API as opportunities without an application
  # - Leads assigned to a job posting show up in Lever as opportunities - potentially multiple per candidate. These show up in the API as applications against the opportunity - even when no actual application submitted
  def check_no_posting(opp)
    return if Util.has_posting(opp) || Util.is_archived(opp)
    
    location = location_from_tags(opp)
    if location.nil?
      # unable to determine target location from tags
      client.add_tags_if_unset(opp, TAG_ASSIGN_TO_LOCATION_NONE_FOUND)
      nil
    else
      client.remove_tags_if_set(opp, TAG_ASSIGN_TO_LOCATION_NONE_FOUND)
      client.add_tag(opp, TAG_ASSIGN_TO_LOCATION_PREFIX + location[:name])
      client.add_tag(opp, TAG_ASSIGNED_TO_LOCATION)
      # add_note(opp, 'Assigned to cohort job: ' + location[:name] + ' based on tags')
      client.add_candidate_to_posting(opp["id"], location[:posting_id])
      true
    end
  end
  
  # record change detected and send webhook
  def notify_of_change(opp, last_update)
    unless opp['applications'].length == 0
      send_webhooks(opp, last_update[:time])
    end
    update_bigquery(opp, last_update[:time])
    update_changed_tag(opp, last_update[:time])
  end
  
  def send_webhooks(opp, update_time=nil)
    log.log("Sending full webhooks - change detected") if FULL_WEBHOOK_URLS.any?
    FULL_WEBHOOK_URLS.each {|url|
      _webhook(url, opp, update_time, true)
    }
    log.log("Sending webhooks - other change detected") if OPPORTUNITY_CHANGED_WEBHOOK_URLS.any?
    OPPORTUNITY_CHANGED_WEBHOOK_URLS.each {|url|
      _webhook(url, opp, update_time, false)
    }
  end
  
  def _webhook(url, opp, update_time, full_data=false)
    p = fork {
      result = HTTParty.post(
        url,
        body: {
          # id: '',
          triggeredAt: update_time,
          event: 'candidateChange_EFAutomationBot',
          # signature: '',
          # token: '',
          data: full_data ? Util.opp_view_data(opp) : {
            candidateId: opp['id'],
            contactId: opp['contact'],
            opportunityId: opp['id']
          }
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
      Util.log_if_api_error(log, result)
    }
    Process.detach(p)
  end

  def update_bigquery(opp, update_time=nil)
    bigquery.insert_async_ensuring_columns(Util.flatten_hash(Util.opp_view_data(opp).merge({"#{BIGQUERY_IMPORT_TIMESTAMP_COLUMN}": update_time || opp['lastInteractionAt']})))
  end

  def update_changed_tag(opp, update_time=nil)
    if update_time.nil?
      update_time = client.get_opportunity(opp['id']).fetch('lastInteractionAt', Time.now.to_i*1000)
    end
    set_bot_metadata(opp, 'last_change_detected', update_time)
  end
  
  # detect when opportunity was last updated
  # uses current time if we detect tags have changed
  def latest_change(opp)
    [
      {time: opp["lastInteractionAt"], source: 'a new interaction'},
      tags_have_changed?(opp),
      links_have_changed?(opp)
    ].reject {|x| x.nil?}.max_by {|x| x[:time]}
  end

  # detect if tags have changed since we last checked, based on special checksum tag
  def tags_have_changed?(opp)
    checksum = attribute_checksum(opp, 'tags')
    existing = existing_tag_checksum(opp)
    
    if existing != checksum
      set_bot_metadata(opp, 'tag_checksum', checksum)
    end

    if existing != checksum && !existing.nil?
      {
        time: Time.now.to_i*1000,
        source: "tags updated\n#" + opp['tags'].sort.reject {|t| t.start_with?(BOT_TAG_PREFIX)}.map {|t| t.gsub(/[ \(\):]/, '-').sub('🤖-[auto]-', '')}.join(' #')
      }
    else
      nil
    end
  end
  
  # detect if links have changed since we last checked, based on special checksum link
  def links_have_changed?(opp)
    checksum = attribute_checksum(opp, 'links')
    existing = existing_link_checksum(opp)

    if existing != checksum
      set_bot_metadata(opp, 'link_checksum', checksum)
    end

    if existing != checksum && !existing.nil?
      {
        time: Time.now.to_i*1000,
        source: "links updated\n📎 " + opp['links'].sort{|a,b| a.sub(/[a-z]+:\/\//,'') <=> b.sub(/[a-z]+:\/\//,'')}.reject {|t| t.start_with?(BOT_LINK_PREFIX)}.join("\n📎 ")
      }
    else
      nil
    end
  end
  
  # calculate checksum for tags/links
  # - excludes bot-applied
  def attribute_checksum(opp, type)
    Digest::MD5.hexdigest(opp[type].reject {|t|
      t.start_with?(type == 'tags' ? BOT_TAG_PREFIX : BOT_LINK_PREFIX)
      }.sort.join(";;"))
  end
  
  def existing_tag_checksum(opp)
    return bot_metadata(opp)['tag_checksum'] if bot_metadata(opp)['tag_checksum']
    # legacy
    opp['tags'].each { |t|
      if t.start_with? TAG_CHECKSUM_PREFIX
        checksum = t.delete_prefix TAG_CHECKSUM_PREFIX
        set_bot_metadata(opp, 'tag_checksum', checksum)
        return checksum
      end
    }
    nil
  end
  
  def existing_link_checksum(opp)
    return bot_metadata(opp)['link_checksum'] if bot_metadata(opp)['link_checksum']
    # legacy
    opp['links'].each { |t|
      if t.start_with? LINK_CHECKSUM_PREFIX
        checksum = t.delete_prefix LINK_CHECKSUM_PREFIX
        set_bot_metadata(opp, 'link_checksum', checksum)
        return checksum
      end
    }
    nil
  end

  def last_change_detected(opp)
    bot_metadata(opp)['last_change_detected'].to_i
  end
  
  def prepare_app_responses(opp)
    # responses to questions are subdivided by custom question set - need to combine them together
    opp['_app_responses'] = []
    opp['_app_responses'] = opp['applications'][0]['customQuestions'].reduce([]) {|a, b| a+b['fields']} if opp.dig('applications', 0, 'customQuestions')
    simple_response_text(opp['_app_responses'])    
  end
  
  def simple_response_text(responses)
    # simply question titles to lowercase a-z only to minimise mismatch due to inconsistent naming
    responses.map! { |qu|
      qu.merge!({
        _text: Util.simplify_str(qu['text']),
        _value: Util.simplify_str(Array(qu['value']).join(' '))
      })
    }
  end
  
  def add_links(opp)
    return if bot_metadata(opp)['link_rules'] == links_rules_checksum
    new_links = rules.update_links(opp)
    return unless Array(new_links).any?
    set_bot_metadata(opp, 'link_rules', links_rules_checksum)
  end
  
  def links_rules_checksum
    @links_rules_checksum ||= Digest::MD5.hexdigest(rules.method('update_links').source)
  end
  
  def summarise_feedbacks(opp)
    if (opp['lastInteractionAt'] > last_change_detected(opp)) || feedback_outdated(opp)
      # summarise each feedback
      client.feedback_for_opp(opp).each {|f|
        simple_response_text(f['fields'])
        link = one_feedback_summary_link(f)
        next if opp['links'].include?(link)
        client.remove_links_with_prefix(opp, one_feedback_summary_link_prefix(f))
        client.add_links(opp, link)
      }
    end

    all_link = all_feedback_summary_link(opp)
    unless opp['links'].include?(all_link)
      client.remove_links_with_prefix(opp, LINK_ALL_FEEDBACK_SUMMARY_PREFIX)
    end
    unless all_link.nil? || opp['links'].include?(all_link)
      client.add_links(opp, all_link)
    end
  end
  
  def feedback_outdated(opp)
    opp['links'].select { |l|
      l.start_with?(AUTO_LINK_PREFIX + 'feedback/') && !l.include?('/feedback/all/') && !l.include?("/#{feedback_rules_checksum}?")
    }.any?
  end

  def feedback_rules_checksum
    @feedback_rules_checksum ||= Digest::MD5.hexdigest(rules.method('summarise_one_feedback').source)
  end
  
  def one_feedback_summary_link_prefix(f)
    AUTO_LINK_PREFIX + "feedback/#{f['id']}/"
  end
  
  def one_feedback_summary_link(f)
    one_feedback_summary_link_prefix(f) + feedback_rules_checksum + '?' + URI.encode_www_form(rules.summarise_one_feedback(f).sort)
  end
  
  def all_feedback_summary_link(opp)
    feedback_data = opp['links'].select { |l|
        l.start_with?(AUTO_LINK_PREFIX + 'feedback/') && !l.include?('/feedback/all/')
      }.map { |l|
        URI.decode_www_form(l.sub(/[^?]*\?/, '')).to_h
      }
    return unless feedback_data.any?
    summary = rules.summarise_all_feedback(feedback_data)
    return unless summary.any?
    LINK_ALL_FEEDBACK_SUMMARY_PREFIX + '?' + URI.encode_www_form(summary.sort)
  end
  
  # determine intended cohort location from lead tags
  def location_from_tags(opp)
    opp["tags"].each { |tag|
      COHORT_JOBS.each { |cohort|
        return cohort if tag.downcase.include?(cohort[:name])
      }
    }
    nil
  end

  def bot_metadata(opp)
    opp['_bot_metadata'] ||= URI.decode_www_form((opp['links'].select {|l| l.start_with? BOT_METADATA_PREFIX + opp['id'] }.first || '').sub(/[^?]*\?/, '')).to_h
  end
  
  def set_bot_metadata(opp, key, value)
    bot_metadata(opp)
    opp['_bot_metadata'][key] = value
  end
  
  def commit_bot_metadata(opp)
    return unless (opp['_bot_metadata'] || {}).any?
    prefix = BOT_METADATA_PREFIX + opp['id'] + '?'
    link = prefix + URI.encode_www_form(opp['_bot_metadata'].sort)
    return if opp['links'].select{|l| l.start_with?(prefix)} == [link]
    client.remove_links_with_prefix(opp, prefix)
    client.add_links(opp, link)
    true
  end

  def remove_legacy_attributes(opp)
    client.remove_links_with_prefix(opp, BOT_METADATA_PREFIX.chomp('/') + '?')
    client.remove_links_with_prefix(opp, LINK_CHECKSUM_PREFIX)
    client.remove_tags_with_prefix(opp, TAG_CHECKSUM_PREFIX)
    client.remove_tags_with_prefix(opp, LAST_CHANGE_TAG_PREFIX)
    client.remove_tags_with_prefix(opp, '🤖 [auto]')
    client.remove_tags_if_set(opp, [TAG_LINKEDIN_OPTOUT_OLD])
  end

end
