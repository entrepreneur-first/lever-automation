# frozen_string_literal: true

require_relative '../config/config'
require_relative 'util'
require_relative 'log'
require_relative 'client'
require_relative '../config/rules'

class Controller

  def initialize
    @log = Log.new
    @client = Client.new(ENV['LKEY'], @log)
  end
  
  def client
    @client
  end
  
  def log
    @log
  end

  def summarise_opportunities
    summary = Hash.new(0)
    contacts = Hash.new(0)
    tagable = Hash.new(0)
    untagable = Hash.new(0)
    
    client.process_paged_result(OPPORTUNITIES_URL, {archived: false, expand: ['applications','stage','sourcedBy','owner']}, 'active opportunities') { |opp|
    
      contacts[opp['contact']] += 1
      summary[:opportunities] += 1
      summary[:unique_contacts] += 1 if contacts[opp['contact']] == 1
      summary[:contacts_with_duplicates] += 1 if contacts[opp['contact']] == 2
      summary[:contacts_with_3_plus] += 1 if contacts[opp['contact']] == 3

      location = location_from_tags(opp) if opp['applications'].length == 0
      summary[:unassigned_leads_aka_opportunities_without_posting] += 1 if opp['applications'].length == 0
      summary[:unassigned_leads_with_detected_location] += 1 if opp['applications'].length == 0 && !location.nil?
      summary[:unassigned_leads_without_detected_location] += 1 if opp['applications'].length == 0 && location.nil?

      # puts location[:name] if opp['applications'].length == 0 && !location.nil?
      tagable['unassigned_tagable_to_' + location[:name]] += 1 if opp['applications'].length == 0 && !location.nil?
      tagable['unassigned_tagable_owned_by_' + (opp.dig('owner','name') || '')] += 1 if opp['applications'].length == 0 && !location.nil?
      tagable['unassigned_tagable_sourced_by_' + (opp.dig('sourcedBy','name') || '')] += 1 if opp['applications'].length == 0 && !location.nil?
      
      untagable['untagable_owned_by_' + (opp.dig('owner','name') || '')] += 1 if opp['applications'].length == 0 && location.nil?
      untagable['untagable_sourced_by_' + (opp.dig('sourcedBy','name') || '')] += 1 if opp['applications'].length == 0 && location.nil?
      
      summary[:cohort_applications] += 1 if Util.has_application(opp) && Util.is_cohort_app(opp)
      summary[:team_applications] += 1 if Util.has_application(opp) && !Util.is_cohort_app(opp)

      summary[:leads_assigned_to_cohort_posting] += 1 if opp['applications'].length > 0 && opp['applications'][0]['type'] != 'posting' && Util.is_cohort_app(opp)
      summary[:leads_assigned_to_team_posting] += 1 if opp['applications'].length > 0 && opp['applications'][0]['type'] != 'posting' && !Util.is_cohort_app(opp)
      
      if summary[:opportunities] % 50 == 0
        # log.log(JSON.pretty_generate(contacts))
        puts JSON.pretty_generate(summary)
        puts JSON.pretty_generate(tagable)
        puts JSON.pretty_generate(untagable)
      end
    }
    log.log(JSON.pretty_generate(summary))
    log.log(JSON.pretty_generate(tagable))
    log.log(JSON.pretty_generate(untagable))
  end

  def process_opportunities
    summary = Hash.new(0)
    contacts = Hash.new(0)

    client.batch_tag_updates

    client.process_paged_result(OPPORTUNITIES_URL, {archived: false, expand: ['applications','stage','sourcedBy','owner']}, 'active opportunities') { |opp|
    
      contacts[opp['contact']] += 1
      summary[:opportunities] += 1
      summary[:unique_contacts] += 1 if contacts[opp['contact']] == 1
      summary[:contacts_with_duplicates] += 1 if contacts[opp['contact']] == 2
      summary[:contacts_with_3_plus] += 1 if contacts[opp['contact']] == 3

      result = process_opportunity(opp)
      
      summary[:sent_webhook] += 1 if result['sent_webhook']
      summary[:assigned_to_job] += 1 if result['assigned_to_job']
      summary[:added_source_tag] += 1 if result['added_source_tag']

      # puts JSON.pretty_generate(summary) if summary[:opportunities] % 100 == 0
      log.log(JSON.pretty_generate(summary)) if summary[:opportunities] % 500 == 0
      # break if summary[:opportunities] % 100 == 0
    }
    client.batch_tag_updates(false)

    log.log(JSON.pretty_generate(summary))
  end

  # process a single opportunity
  # apply changes & trigger webhook as necessary
  def process_opportunity(opp)
    result = {}
    # log('Processing Opportunity: ' + opp['id'])
    log.log_prefix(opp['id'] + ': ')

    # checks lastInteractionAt and tag checksum, creating checksum tag if necessary
    last_update = latest_change(opp)
    # should notify of change based on state before we executed?
    notify = last_update[:time] > last_webhook_change(opp) + 100
    # log(last_update.to_s)
    # log(last_webhook_change(opp).to_s)
    # has_tag_change = tags_have_changed?(opp)

    if check_no_posting(opp)
      # if we added to a job then reload as tags etc will have changed
      opp.merge!(client.get_opportunity(opp['id']))
      result['assigned_to_job'] = true
    end
    result['added_source_tag'] if tag_source_from_application(opp)

    # detect_duplicate_opportunities(opp)

    tags_changed_update = tags_have_changed?(opp)
    unless tags_changed_update.nil?
      last_update = tags_changed_update
      notify = true
    end

    if notify
      # send webhook of change
      notify_of_change(opp, last_update)
      result['sent_webhook'] = true
    elsif opp['_addedNoteTimestamp']
      # we didn't have a change to notify, but we added one or more notes
      # which will update lastInteractionAt
      # so update LAST_CHANGE_TAG to avoid falsely detecting update next time
      update_changed_tag(opp, opp['_addedNoteTimestamp'])
    end

    client.commit_opp(opp)

    log.pop_log_prefix
    result
  end

  # process leads not assigned to any posting
  # ~~
  # Note slight confusion between Lever interface vs API:
  # - Leads not assigned to a job posting show up in Lever as candidates with "no opportunity", but are returned in the API as opportunities without an application
  # - Leads assigned to a job posting show up in Lever as opportunities - potentially multiple per candidate. These show up in the API as applications against the opportunity - even when no actual application submitted
  def check_no_posting(opp)
    return if opp["applications"].count > 0
    location = location_from_tags(opp)
    if location.nil?
      # unable to determine target location from tags
      client.add_tag(opp, TAG_ASSIGN_TO_LOCATION_NONE_FOUND) unless opp['tags'].include?(TAG_ASSIGN_TO_LOCATION_NONE_FOUND)
      nil
    else
      client.remove_tag(opp, TAG_ASSIGN_TO_LOCATION_NONE_FOUND) if opp['tags'].include?(TAG_ASSIGN_TO_LOCATION_NONE_FOUND)
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
      send_webhook(opp, last_update[:time])
      client.add_note(opp, 'Updated reporting data after detecting ' + last_update[:source])
    end
    update_changed_tag(opp)
  end
  
  def send_webhook(opp, update_time)
    log.log("Sending webhook - change detected") #: " + opp["id"])
    OPPORTUNITY_CHANGED_WEBHOOK_URLS.each {|url|
      result = HTTParty.post(
        url,
        body: {
          # id: '',
          triggeredAt: update_time,
          event: 'candidateOtherChange_EFCustomBot',
          # signature: '',
          # token: '',
          data: {
            candidateId: opp['id'],
            contactId: opp['contact'],
            opportunityId: opp['id']
          }
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
    }
  end

  def update_changed_tag(opp, update_time=nil)
    if update_time.nil?
      update_time = client.get_opportunity(opp['id']).fetch('lastInteractionAt', Time.now.to_i*1000)
    end
    client.remove_tags_with_prefix(opp, LAST_CHANGE_TAG_PREFIX)
    client.add_tag(opp, LAST_CHANGE_TAG_PREFIX + Util.timestamp_to_datetimestr(update_time))
  end
  
  # detect when opportunity was last updated
  # uses current time if we detect tags have changed
  def latest_change(opp)
    [
      {time: opp["lastInteractionAt"], source: 'a new interaction'},
      tags_have_changed?(opp)
    ].reject {|x| x.nil?}.max_by {|x| x[:time]}
  end

  # detect if tags have changed since we last checked, based on special checksum tag
  def tags_have_changed?(opp)
    checksum = tag_checksum(opp)
    existing = existing_tag_checksum(opp)
    
    if existing != checksum
      client.remove_tags_with_prefix(opp, TAG_CHECKSUM_PREFIX)
      client.add_tag(opp, TAG_CHECKSUM_PREFIX + checksum)
    end

    {
      time: Time.now.to_i*1000,
      source: "tags updated\n#" + opp['tags'].sort.reject {|t| t.start_with?(BOT_TAG_PREFIX)}.map {|t| t.gsub(/[ \(\):]/, '-').sub('🤖-[auto]-', '')}.join(' #')
    } if existing != checksum && !existing.nil?
  end
  
  # calculate checksum for tags
  # - excludes bot-applied tags
  def tag_checksum(opp)
    Digest::MD5.hexdigest(opp["tags"].reject {|t| t.start_with?(LAST_CHANGE_TAG_PREFIX) || t.start_with?(TAG_CHECKSUM_PREFIX)}.sort.join(";;"))
  end
  
  def existing_tag_checksum(opp)
    opp["tags"].each { |t|
      return t.delete_prefix TAG_CHECKSUM_PREFIX if t.start_with? TAG_CHECKSUM_PREFIX
    }
    nil
  end
  
  # detect time of last change that would have triggered a Lever native webhook
  # - either a lever Native webhook (created, stage change or application),
  #   or a webhook we send ourselves via this script (recorded via tag)
  def last_webhook_change(opp)
    (
      [opp["createdAt"], opp["lastAdvancedAt"]] +
      opp["applications"].map {|a| a["createdAt"]} +
      (opp["tags"].select {|t| t.start_with? LAST_CHANGE_TAG_PREFIX}.map {|t| Util.datetimestr_to_timestamp(t.delete_prefix(LAST_CHANGE_TAG_PREFIX)) })
    ).reject {|x| x.nil?}.max
  end
  
  # automatically add tag for the opportunity source based on self-reported data in the application
  def tag_source_from_application(opp)
    client.remove_tag(opp, TAG_SOURCE_FROM_APPLICATION_ERROR) if opp['tags'].include? TAG_SOURCE_FROM_APPLICATION_ERROR
    
    # we need an application of type posting, to the cohort (not team job)
    return if !Util.has_application(opp) || !Util.is_cohort_app(opp)
    
    # skip if already applied
    opp['tags'].each {|tag|
      return if tag.start_with?(TAG_SOURCE_FROM_APPLICATION) && tag != TAG_SOURCE_FROM_APPLICATION_ERROR
    }
    
    source = Rules.source_from_application(opp)
    unless source.nil? || source[:source].nil?
      client.add_tag(opp, TAG_SOURCE_FROM_APPLICATION + source[:source])
      client.remove_tag(opp, TAG_SOURCE_FROM_APPLICATION_ERROR) if opp['tags'].include? TAG_SOURCE_FROM_APPLICATION_ERROR
      client.add_note(opp, 'Added tag ' + TAG_SOURCE_FROM_APPLICATION + source[:source] + "\nbecause field \"" + source[:field] + "\"\nis \"" + (source[:value].class == Array ?
        source[:value].join('; ') :
        source[:value]) + '"')
    else
      client.add_tag(opp, TAG_SOURCE_FROM_APPLICATION_ERROR) if !opp['tags'].include? TAG_SOURCE_FROM_APPLICATION_ERROR
    end
    true
  end
    
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

  # determine intended cohort location from lead tags
  def location_from_tags(opp)
    opp["tags"].each { |tag|
      COHORT_JOBS.each { |cohort|
        return cohort if tag.downcase.include?(cohort[:name])
      }
    }
    nil
  end

  # TEMP
  
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
      api_call_log(log_string, page) do
        result = HTTParty.get(OPPORTUNITIES_URL + Util.to_query(params.merge(offset: next_batch)), basic_auth: auth)
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
      client.add_tag(opp, TAG_ASSIGNED_TO_LOCATION, true) if opp['applications'][0]['user'] == LEVER_BOT_USER && !opp['tags'].include?(TAG_ASSIGNED_TO_LOCATION)
      client.remove_tag(opp, TAG_SOURCE_FROM_APPLICATION_ERROR) if !Util.has_application(opp) || !Util.is_cohort_app(opp)
    }
  end

end