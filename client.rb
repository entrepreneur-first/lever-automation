# frozen_string_literal: true

require 'date'
require 'digest/md5'
require 'httparty'
require 'uri'
require 'logger'

LOG_FILE = 'logs/' + Time.now().strftime('%Y-%m-%d') + '.log'
ERROR_LOG_FILE = 'logs/' + Time.now().strftime('%Y-%m-%d') + '_error.log'

LEVER_BOT_USER = 'e6414a92-e785-46eb-ad30-181c18db19b5'

API_URL = 'https://api.lever.co/v1/'
OPPORTUNITIES_URL = API_URL + 'opportunities'

OPPORTUNITY_CHANGED_WEBHOOK_URLS = ['https://hooks.zapier.com/hooks/catch/6688770/o55rf2n/', 'https://hooks.zapier.com/hooks/catch/3678640/o1tu42p/']

AUTO_TAG_PREFIX = '🤖 [auto] '
BOT_TAG_PREFIX = '🤖 [bot] '

LAST_CHANGE_TAG_PREFIX = BOT_TAG_PREFIX + "last change detected: "
TAG_CHECKSUM_PREFIX = BOT_TAG_PREFIX + "tag checksum: "

TAG_ASSIGN_TO_LOCATION_NONE_FOUND = AUTO_TAG_PREFIX + 'no location tag detected'
TAG_ASSIGN_TO_LOCATION_PREFIX = AUTO_TAG_PREFIX + 'auto-assigned to cohort: '
TAG_ASSIGNED_TO_LOCATION = AUTO_TAG_PREFIX + 'auto-assigned to cohort'

TAG_DUPLICATE_OPPS_PREFIX = AUTO_TAG_PREFIX + "duplicate opportunity "
TAG_SOURCE_FROM_APPLICATION = AUTO_TAG_PREFIX + 'self-reported source: '
TAG_SOURCE_FROM_APPLICATION_ERROR = TAG_SOURCE_FROM_APPLICATION + 'ERROR unknown'

COHORT_JOBS = [
  {name: 'bangalore', posting_id: '23bf8c07-b32e-483f-9007-1b9c2a004eb6'},
  {name: 'london', posting_id: 'c404cfc6-0621-4fce-9e76-5d908e36fd9c'},
  {name: 'singapore', posting_id: '3b2c714a-edee-4fd0-974d-413bae32c818'},
  {name: 'paris', posting_id: 'e23deb1a-c0ab-43b8-9a3a-e47e3cca0970'},
  {name: 'berlin', posting_id: 'b9c2b6b8-3d82-4c45-9b06-b549d223b017'},
  {name: 'toronto', posting_id: '0b785d4c-3a6e-4597-829e-fcafb06cae2b'}
]

BASE_PARAMS = {
  limit: 100
}.freeze

OPPORTUNITIES_PARAMS = {
  expand: %w[applications stage owner followers]
}.freeze

class Client
  def initialize(username)
    @username = username
    @password = ''
    
    @log = Logger.new(ENV['LOG_FILE'].nil? ? STDOUT : LOG_FILE)
    @log.formatter = proc { |severity, datetime, progname, msg| ENV['LOG_FILE'].nil? ? "#{msg}\n" : "#{severity}, #{datetime}, #{msg}\n" }
    @log_prefix = []
    @error_log = Logger.new(ENV['LOG_FILE'].nil? ? STDOUT : ERROR_LOG_FILE)
    @error_log.formatter = proc { |severity, datetime, progname, msg| ENV['LOG_FILE'].nil? ? "#{msg}\n" : "#{severity}, #{datetime}, #{msg}\n" }
  end

  def summarise_opportunities
    summary = Hash.new(0)
    contacts = Hash.new(0)
    tagable = Hash.new(0)
    untagable = Hash.new(0)
    
    process_paged_result(OPPORTUNITIES_URL, {archived: false, expand: ['applications','stage','sourcedBy','owner']}, 'active opportunities') { |opp|
    
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
      
      summary[:cohort_applications] += 1 if has_application(opp) && is_cohort_app(opp)
      summary[:team_applications] += 1 if has_application(opp) && !is_cohort_app(opp)

      summary[:leads_assigned_to_cohort_posting] += 1 if opp['applications'].length > 0 && opp['applications'][0]['type'] != 'posting' && is_cohort_app(opp)
      summary[:leads_assigned_to_team_posting] += 1 if opp['applications'].length > 0 && opp['applications'][0]['type'] != 'posting' && !is_cohort_app(opp)
      
      if summary[:opportunities] % 50 == 0
        # log(JSON.pretty_generate(contacts))
        puts JSON.pretty_generate(summary)
        puts JSON.pretty_generate(tagable)
        puts JSON.pretty_generate(untagable)
      end
    }
    log(JSON.pretty_generate(summary))
    log(JSON.pretty_generate(tagable))
    log(JSON.pretty_generate(untagable))
  end

  def process_opportunities
    summary = Hash.new(0)
    contacts = Hash.new(0)

    batch_tag_updates

    process_paged_result(OPPORTUNITIES_URL, {archived: false, expand: ['applications','stage','sourcedBy','owner']}, 'active opportunities') { |opp|
    
      contacts[opp['contact']] += 1
      summary[:opportunities] += 1
      summary[:unique_contacts] += 1 if contacts[opp['contact']] == 1
      summary[:contacts_with_duplicates] += 1 if contacts[opp['contact']] == 2
      summary[:contacts_with_3_plus] += 1 if contacts[opp['contact']] == 3

      result = process_opportunity(opp)
      summary[:sent_webhook] += 1 if result['sent_webhook']
      summary[:assigned_to_job] += 1 if result['assigned_to_job']
      summary[:added_source_tag] += 1 if result['added_source_tag']

      puts JSON.pretty_generate(summary) if summary[:opportunities] % 10 == 0
      log(JSON.pretty_generate(summary)) if summary[:opportunities] % 500 == 0
      # break if summary[:opportunities] % 100 == 0
    }
    batch_tag_updates(false)

    log(JSON.pretty_generate(summary))
  end

  # process a single opportunity
  # apply changes & trigger webhook as necessary
  def process_opportunity(opp)
    result = {}
    log('Processing Opportunity: ' + opp['id'])
    log_prefix('| ')

    # checks lastInteractionAt and tag checksum, creating checksum tag if necessary
    last_update = latest_change(opp)
    # should notify of change based on state before we executed?
    notify = last_update[:time] > last_webhook_change(opp) + 100
    # log(last_update.to_s)
    # log(last_webhook_change(opp).to_s)
    # has_tag_change = tags_have_changed?(opp)

    if check_no_posting(opp)
      # if we added to a job then reload as tags etc will have changed
      opp.merge!(get_opportunity(opp['id']))
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

    commit_opp(opp)

    pop_log_prefix
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
      add_tag(opp, TAG_ASSIGN_TO_LOCATION_NONE_FOUND) unless opp['tags'].include?(TAG_ASSIGN_TO_LOCATION_NONE_FOUND)
      nil
    else
      remove_tag(opp, TAG_ASSIGN_TO_LOCATION_NONE_FOUND) if opp['tags'].include?(TAG_ASSIGN_TO_LOCATION_NONE_FOUND)
      add_tag(opp, TAG_ASSIGN_TO_LOCATION_PREFIX + location[:name])
      add_tag(opp, TAG_ASSIGNED_TO_LOCATION)
      # add_note(opp, 'Assigned to cohort job: ' + location[:name] + ' based on tags')
      add_candidate_to_posting(opp["id"], location[:posting_id])
      true
    end
  end
  
  # record change detected and send webhook
  def notify_of_change(opp, last_update)
    unless opp['applications'].length == 0
      send_webhook(opp, last_update[:time])
      add_note(opp, 'Updated reporting data after detecting ' + last_update[:source])
    end
    update_changed_tag(opp)
  end
  
  def send_webhook(opp, update_time)
    log("Sending webhook - change detected for: " + opp["id"])
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
      update_time = get_opportunity(opp['id']).fetch('lastInteractionAt', Time.now.to_i*1000)
    end
    remove_tags_with_prefix(opp, LAST_CHANGE_TAG_PREFIX)
    add_tag(opp, LAST_CHANGE_TAG_PREFIX + timestamp_to_datetimestr(update_time))
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
    
    (remove_tags_with_prefix(opp, TAG_CHECKSUM_PREFIX)
; add_tag(opp, TAG_CHECKSUM_PREFIX + checksum)) if existing != checksum

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
      (opp["tags"].select {|t| t.start_with? LAST_CHANGE_TAG_PREFIX}.map {|t| datetimestr_to_timestamp(t.delete_prefix(LAST_CHANGE_TAG_PREFIX)) })
    ).reject {|x| x.nil?}.max
  end
  
  # automatically add tag for the opportunity source based on self-reported data in the application
  def tag_source_from_application(opp)
    remove_tag(opp, TAG_SOURCE_FROM_APPLICATION_ERROR) if opp['tags'].include? TAG_SOURCE_FROM_APPLICATION_ERROR
    
    # we need an application of type posting, to the cohort (not team job)
    return if !has_application(opp) || !is_cohort_app(opp)
    
    # skip if already applied
    opp['tags'].each {|tag|
      return if tag.start_with?(TAG_SOURCE_FROM_APPLICATION) && tag != TAG_SOURCE_FROM_APPLICATION_ERROR
    }
    
    source = source_from_application(opp)
    unless source.nil? || source[:source].nil?
      add_tag(opp, TAG_SOURCE_FROM_APPLICATION + source[:source])
      remove_tag(opp, TAG_SOURCE_FROM_APPLICATION_ERROR) if opp['tags'].include? TAG_SOURCE_FROM_APPLICATION_ERROR
      add_note(opp, 'Added tag ' + TAG_SOURCE_FROM_APPLICATION + source[:source] + "\nbecause field \"" + source[:field] + "\"\nis \"" + (source[:value].class == Array ? source[:value].join('; ') : source[:value]) + '"')
    else
      add_tag(opp, TAG_SOURCE_FROM_APPLICATION_ERROR) if !opp['tags'].include? TAG_SOURCE_FROM_APPLICATION_ERROR
    end
    true
  end
  
  def source_from_application(opp)
    return {msg: 'No application'} if !has_application(opp)
    # responses to questions are subdivided by custom question set - need to combine them together
    responses = opp['applications'][0]['customQuestions'].reduce([]) {|a, b| a+b['fields']} if opp.dig('applications', 0, 'customQuestions')
    return {msg: "Couldn't find custom question responses."} if responses.nil?

    # simply question titles to lowercase a-z only to minimise mismatch due to inconsistent naming
    responses.map! { |qu|
      qu.merge!({
        _text: qu['text'].downcase.gsub(/[^a-z ]/, ''),
        _value: (qu['value'].class == Array ? qu['value'].join(' ') : qu['value']).downcase.gsub(/[^a-z ]/, ''),
      })
    }

    # 1: "who referred you"
    responses.each {|qu|
      if qu[:_text].include?('who referred you')
        return {source: "Referral", field: qu['text'], value: "<not empty>"} if qu['value'] > ''
        break
      end
    }

    responses.each {|qu|
      if qu[:_text].include?('who told you about ef')
        map = [
          ['been on the ef programme', 'Referral'],
          ['worked at ef', 'Referral'],
          ['professional network', 'Organic'],
          ['friends or family', 'Organic']
        ]
        source = nil
        map.each { |m|
          source = m[1] if qu[:_value].include? m[0]
        }
        return {source: source, field: qu['text'], value: qu['value']} unless source.nil?
        break
      end
    }

    responses.each {|qu|
      if qu[:_text].include?('how did you hear about ef')
        map = [
          ['directly contacted by ef', 'Sourced'],
          ['cohort member', 'Referral'],
          ['someone else', 'Organic'], # if not already covered above by latter questions
          ['came across ef', 'Offline-or-Organic'],
          ['event', 'Offline']
        ]
        source = nil
        map.each { |m|
          source = m[1] if qu[:_value].include? m[0]
        }
        return {source: source, field: qu['text'], value: qu['value']} unless source.nil?
        break
      end
    }
    # otherwise, unable to determine source from application
    nil
  end
  
  def has_application(opp)
    opp['applications'].length > 0 &&
      opp['applications'][0]['type'] == 'posting' &&
      opp['applications'][0]['customQuestions'].length > 0
  end
  
  def is_cohort_app(opp)
    opp['tags'].include?('EF Cohort')
  end
  
  # detect duplicate opportunities for a candidate
  def detect_duplicate_opportunities(opp)
    remove_tags_with_prefix(opp, TAG_DUPLICATE_OPPS_PREFIX) if opp["applications"].count < 2
    posting_ids = opp["applications"].map {|a| a["posting"] || 'none'}
    duplicates = dup_hash(posting_ids)
    # multiple opps, same position
    add_tag(opp, TAG_DUPLICATE_OPPS_PREFIX + " same posting") if duplicates.length > 0
    # multiple opps, for different positions
    add_tag(opp, TAG_DUPLICATE_OPPS_PREFIX + " different posting") if posting_ids.reject {|p| p == 'none' }.uniq.length > 1
    # one or more opps for a position, as well as a lead with no job position assigned
    add_tag(opp, TAG_DUPLICATE_OPPS_PREFIX + " without posting") if posting_ids.reject {|p| p == 'none' }.length > 0 && posting_ids.include?("none")
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

  def remove_tags_with_prefix(opp, prefix)
    opp["tags"].each { |tag|
      remove_tag(opp, tag) if tag.start_with? prefix
    }
  end

  def add_bot_tag(opp, tag)
    add_tag(opp, BOT_TAG_PREFIX + tag)
  end
  
  def remove_bot_tag(opp, tag)
    remove_tag(opp, BOT_TAG_PREFIX + tag)
  end
  
  def batch_tag_updates(batch=true)
    @batch_tag_updates = batch
  end
  
  def queue_add_tag(opp, tags)
    tags = [tags] if tags.class != Array
    tags.each { |tag|
      opp['_addTags'] = [] if opp['_addTags'].nil?
      opp['_addTags'] << tag unless opp['_addTags'].include?(tag)
      opp['tags'] << tag unless opp['tags'].include?(tag)
      opp['_removeTags'].delete(tag) unless opp['_removeTags'].nil?
    }
  end
  
  def queue_remove_tag(opp, tags)
    tags = [tags] if tags.class != Array
    tags.each { |tag|
      opp['_removeTags'] = [] if opp['_removeTags'].nil?
      opp['_removeTags'] << tag unless opp['_removeTags'].include?(tag) || (!opp['_addTags'].nil? && opp['_addTags'].include?(tag))
      opp['_addTags'].delete(tag) unless opp['_addTags'].nil?
      opp['tags'].delete(tag)
    }
  end
  
  def commit_opp(opp)
    add_tag(opp, opp['_addTags'], true) unless opp['_addTags'].nil? || opp['_addTags'].length == 0
    remove_tag(opp, opp['_removeTags'], true) unless opp['_removeTags'].nil? || opp['_removeTags'].length == 0
  end
  
  def add_tag(opp, tags, commit=false)
    tags = [tags] if tags.class != Array
    return queue_add_tag(opp, tags) if @batch_tag_updates && !commit
    api_action_log("Adding tags: " + opp["id"] + ": " + tags.join(',')) do
      result = HTTParty.post(API_URL + 'opportunities/' + opp["id"] + '/addTags?' + to_query({ perform_as: LEVER_BOT_USER }),
        body: {
          tags: tags
        }.to_json,
        headers: { 'Content-Type' => 'application/json' },
        basic_auth: auth
      )
      tags.each {|tag|
        opp['tags'] += [tag] if !opp['tags'].include?(tag)
      }
      result
    end
  end
  
  def remove_tag(opp, tags, commit=false)
    tags = [tags] if tags.class != Array
    return queue_remove_tag(opp, tags) if @batch_tag_updates && !commit
    api_action_log("Removing tags: " + opp["id"] + ": " + tags.join(',')) do
      result = HTTParty.post(API_URL + 'opportunities/' + opp["id"] + '/removeTags?' + to_query({ perform_as: LEVER_BOT_USER }),
        body: {
          tags: tags
        }.to_json,
        headers: { 'Content-Type' => 'application/json' },
        basic_auth: auth
      )
      tags.each {|tag|
        opp['tags'].delete(tag)
      }
      result
    end
  end
  
  def add_note(opp, msg, timestamp=nil)
    api_action_log("Adding note: " + opp["id"] + ": " + msg) do
      result = HTTParty.post(API_URL + 'opportunities/' + opp["id"] + '/notes?' + to_query({ perform_as: LEVER_BOT_USER }),
        body: {
          value: msg,
          createdAt: timestamp
        }.reject {|k,v| v.nil?}.to_json,
        headers: { 'Content-Type' => 'application/json' },
        basic_auth: auth
      )
      # record that we have left a note, since this will update the lastInteractionAt timestamp
      # so we should update our LAST_CHANGE_TAG
      opp['_addedNoteTimestamp'] = [opp['_addedNote'] || 0, timestamp || Time.now.to_i*1000]
      result
    end
  end

  # TEMP
  def all_opportunities(posting_ids = [])
    arr = []
    puts "Fetching opportunities"
    arr += opportunities(posting_ids)
    puts "Fetching archived opportuninites"
    arr += archived_opportunities(posting_ids)
    arr
  end

  def process_paged_result(url, params, log_string)
    result = HTTParty.get(url + '?' + to_query(params), basic_auth: auth)
    result.fetch('data').each { |row| yield(row) }
    page = 1
    while result.fetch('hasNext')
      next_batch = result.fetch('next')
      page += 1
      api_call_log(log_string, page) do
        result = HTTParty.get(url + '?' + to_query(params.merge(offset: next_batch)), basic_auth: auth)
      end
      result.fetch('data').each { |row| yield(row) }
    end
  end

  def get_paged_result(url, params={}, log_string='')
    arr = []
    result = HTTParty.get(url + '?' + to_query(params), basic_auth: auth)
    arr += result.fetch('data')
    page = 
    while result.fetch('hasNext')
      next_batch = result.fetch('next')
      page += 1
      api_call_log(log_string, page) do
        result = HTTParty.get(url + '?' + to_query(params.merge(offset: next_batch)), basic_auth: auth)
      end
      arr += result.fetch('data')
      page += 1
    end
    arr
  end

  def get_single_result(url, params={}, log_string='')
    u = url + '?' + to_query(params)
    result = HTTParty.get(u, basic_auth: auth)
    unless result.code >= 200 && result.code < 300
      error(result.parsed_response['code'] + ': ' + result.parsed_response['message'] + ' - ' + u)
    end
    result.fetch('data')
  end
  
  def get_opportunity(id)
    get_single_result(OPPORTUNITIES_URL.chomp('?') + '/' + id)
  end

  def archived_opportunities(posting_ids = [])
    get_paged_result(OPPORTUNITIES_URL, OPPORTUNITIES_PARAMS.merge(archived_posting_id: posting_ids), 'archived_opportunities')
  end

  def opportunities(posting_ids = [])
    get_paged_result(OPPORTUNITIES_URL, OPPORTUNITIES_PARAMS.merge(posting_id: posting_ids), 'opportunities')
  end

  def feedback(opportunities_ids = [])
    arr = []
    total = opportunities_ids.count
    opportunities_ids.each_with_index.each do |opportunity_id, index|
      api_call_log('feedback', "#{index + 1}/#{total}") do
        result = HTTParty.get(feedback_url(opportunity_id), basic_auth: auth)
        arr += result.fetch('data').map { |x| x.merge('opportunity_id' => opportunity_id) }
      end
    end
    arr
  end
  
  def opportunities_for_contact(email)
    get_paged_result(OPPORTUNITIES_URL, {email: email, expand: 'applications'}, 'opportunities_for_contact')
  end
  
  def assign_to_job(email, posting_id)
    ## POST /opportunities/ to create a new opportunity will result in a dupliate opportunity for existing lead
    # result = HTTParty.post(OPPORTUNITIES_URL + to_query({
    #     perform_as: LEVER_BOT_USER
    #   }),
    #   body: {
    #     emails: [email],
    #     tags: ["x-auto-tagged-to-job"],
    #     postings: [posting_id]
    #   }.to_json,
    #   headers: { 'Content-Type' => 'application/json' },
    #   basic_auth: auth
    # )
    
    ## So we use the legacy endpoint to assign a posting to a candidate instead
    opps = opportunities_for_contact(email)
    opps_without_posting = opps.select { |o| o["applications"].count == 0 }
    
    result = []
    opps_without_posting.each { |o|
      result += add_candidate_to_posting(o["id"], posting_id)
    }
    puts result
  end

  def add_candidate_to_posting(candidate_id, posting_id)
    api_action_log("Adding candidate " + candidate_id + " to posting " + posting_id) do
      result = HTTParty.post(API_URL + 'candidates/' + candidate_id + '/addPostings?' + to_query({
          perform_as: LEVER_BOT_USER
        }),
        body: {
          postings: [posting_id]
        }.to_json,
        headers: { 'Content-Type' => 'application/json' },
        basic_auth: auth
      )
      result
    end
  end

  # TEMP
  def opportunities_without_posting
    log_string = 'opportunities_without_posting'
    params = {}
    arr = []
    tags = Hash.new(0)
    result = HTTParty.get(OPPORTUNITIES_URL + to_query(params), basic_auth: auth)
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
        result = HTTParty.get(OPPORTUNITIES_URL + to_query(params.merge(offset: next_batch)), basic_auth: auth)
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
    process_paged_result(OPPORTUNITIES_URL, {archived: false}, 'checking for links') { |opp|
      puts JSON.pretty_generate(opp) if opp['links'].length > 1
    }
  end

  # fixes

  def fix_auto_assigned_tags
    process_paged_result(OPPORTUNITIES_URL, {archived: false, expand: ['applications']}, 'fixing auto-assigned tags for active opportunities') { |opp|
      next if opp['applications'].length == 0
      add_tag(opp, TAG_ASSIGNED_TO_LOCATION, true) if opp['applications'][0]['user'] == LEVER_BOT_USER && !opp['tags'].include?(TAG_ASSIGNED_TO_LOCATION)
      remove_tag(opp, TAG_SOURCE_FROM_APPLICATION_ERROR) if !has_application(opp) || !is_cohort_app(opp)
    }
  end

#  private

  def to_query(hash)
    URI.encode_www_form(BASE_PARAMS.merge(hash))
  end

  def auth
    { username: @username, password: @password }
  end

  def log(msg)
    msg = log_prefix_lines(msg)
    puts msg UNLESS ENV['LOG_FILE'].nil?
    @log.info(msg)
  end

  def warn(msg)
    msg = msg
    puts log_prefix_lines("WARN: " + msg) unless ENV['LOG_FILE'].nil?
    @log.warn(log_prefix_lines(msg))
  end

  def error(msg)
    msg = msg
    puts log_prefix_lines("ERROR: " + msg) unless ENV['LOG_FILE'].nil?
    @log.error(log_prefix_lines(msg))
    @error_log.error(log_prefix_lines(msg))
  end

  def log_prefix(p=nil)
    @log_prefix << p unless p.nil?
    @log_prefix.join
  end

  def pop_log_prefix
    @log_prefix.pop
  end
  
  def log_prefix_lines(msg)
    log_prefix + msg.gsub("\n", "\n" + log_prefix + '  ')
  end

  def api_call_log(resource, page)
    log("Lever API #{resource} page=#{page} start")
    yield
    log("Lever API #{resource} page=#{page} end")
    true
  end

  def api_action_log(msg)
    log(msg)
    result = yield
    # retry on occasional bad gateway error
    if result.code == 502
      warn('502 error, retrying')
      result = yield
    end
    unless result.code >= 200 && result.code < 300
      error(result.code.to_s || '' + ': ' + result.parsed_response['code'] || '<no code>' + ': ' + result.parsed_response['message'] || '<no message>')
    end
    result.parsed_response
  end

  def feedback_url(opportunity_id)
    API_URL + "opportunities/#{opportunity_id}/feedback"
  end
  
  def dup_hash(ary)
    ary.inject(Hash.new(0)) { |h,e| h[e] += 1; h }
      .select { |_k,v| v > 1 }
      .inject({}) { |r, e| r[e.first] = e.last; r }
  end
  
  def datetimestr_to_timestamp(d)
    DateTime.parse(d).strftime('%s').to_i*1000
  end
  
  def timestamp_to_datetimestr(t)
    Time.at((t/1000.0).ceil).utc.to_s
  end
end
