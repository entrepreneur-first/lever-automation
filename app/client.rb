# frozen_string_literal: true

require 'date'
require 'digest/md5'
require 'httparty'
require 'uri'

API_URL = 'https://api.lever.co/v1/'
OPPORTUNITIES_URL = API_URL + 'opportunities'

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
  end

  #
  # Reading data
  #

  def get_opportunity(id)
    get_single_result(OPPORTUNITIES_URL.chomp('?') + '/' + id)
  end

  def opportunities_for_contact(email)
    get_paged_result(OPPORTUNITIES_URL, {email: email, expand: 'applications'}, 'opportunities_for_contact')
  end

  def opportunities(posting_ids = [])
    get_paged_result(OPPORTUNITIES_URL, OPPORTUNITIES_PARAMS.merge(posting_id: posting_ids), 'opportunities')
  end

  def archived_opportunities(posting_ids = [])
    get_paged_result(OPPORTUNITIES_URL, OPPORTUNITIES_PARAMS.merge(archived_posting_id: posting_ids), 'archived_opportunities')
  end

  def all_opportunities(posting_ids = [])
    opportunities(posting_ids) + archived_opportunities(posting_ids)
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

  #
  # Updating data
  #

  def batch_tag_updates(batch=true)
    @batch_tag_updates = batch
  end

  def commit_opp(opp)
    add_tag(opp, opp['_addTags'], true) unless opp['_addTags'].nil? || opp['_addTags'].length == 0
    remove_tag(opp, opp['_removeTags'], true) unless opp['_removeTags'].nil? || opp['_removeTags'].length == 0
  end
  
  def add_tag(opp, tags, commit=false)
    tags = [tags] if tags.class != Array
    return queue_add_tag(opp, tags) if @batch_tag_updates && !commit
    api_action_log("Adding tags: " + tags.join(',')) do
      result = HTTParty.post(API_URL + 'opportunities/' + opp["id"] + '/addTags?' + Util.to_query({ perform_as: LEVER_BOT_USER }),
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
    api_action_log("Removing tags: " + tags.join(',')) do
      result = HTTParty.post(API_URL + 'opportunities/' + opp["id"] + '/removeTags?' + Util.to_query({ perform_as: LEVER_BOT_USER }),
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
    
  def remove_tags_with_prefix(opp, prefix)
    opp["tags"].each { |tag|
      remove_tag(opp, tag) if tag.start_with? prefix
    }
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
  
  def add_note(opp, msg, timestamp=nil)
    api_action_log("Adding note: " + msg) do
      result = HTTParty.post(API_URL + 'opportunities/' + opp["id"] + '/notes?' + Util.to_query({ perform_as: LEVER_BOT_USER }),
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

  def assign_to_job(email, posting_id)
    ## POST /opportunities/ to create a new opportunity will result in a dupliate opportunity for existing lead
    # result = HTTParty.post(OPPORTUNITIES_URL + Util.to_query({
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
    api_action_log("Adding to posting " + posting_id) do
      result = HTTParty.post(API_URL + 'candidates/' + candidate_id + '/addPostings?' + Util.to_query({
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

  #
  # Helpers
  #
  
  def get_single_result(url, params={}, log_string='')
    u = url + '?' + Util.to_query(params)
    result = HTTParty.get(u, basic_auth: auth)
    unless result.code >= 200 && result.code < 300
      error(result.parsed_response['code'] + ': ' + result.parsed_response['message'] + ' - ' + u)
    end
    result.fetch('data')
  end
    
  def process_paged_result(url, params, log_string)
    result = HTTParty.get(url + '?' + Util.to_query(params), basic_auth: auth)
    result.fetch('data').each { |row| yield(row) }
    page = 1
    while result.fetch('hasNext')
      next_batch = result.fetch('next')
      page += 1
      api_call_log(log_string, page) do
        result = HTTParty.get(url + '?' + Util.to_query(params.merge(offset: next_batch)), basic_auth: auth)
      end
      result.fetch('data').each { |row| yield(row) }
    end
  end

  def get_paged_result(url, params={}, log_string='')
    arr = []
    result = HTTParty.get(url + '?' + Util.to_query(params), basic_auth: auth)
    arr += result.fetch('data')
    page = 
    while result.fetch('hasNext')
      next_batch = result.fetch('next')
      page += 1
      api_call_log(log_string, page) do
        result = HTTParty.get(url + '?' + Util.to_query(params.merge(offset: next_batch)), basic_auth: auth)
      end
      arr += result.fetch('data')
      page += 1
    end
    arr
  end  

  #
  # Wrappers for making API calls with logging
  #

  def api_call_log(resource, page)
    log("Lever API #{resource} page=#{page} start") if @log_verbose
    yield
    log("Lever API #{resource} page=#{page} end") if @log_verbose
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

  #
  private
  #

  def auth
    { username: @username, password: @password }
  end
  
  def feedback_url(opportunity_id)
    API_URL + "opportunities/#{opportunity_id}/feedback"
  end
  
  #def add_bot_tag(opp, tag)
  #  add_tag(opp, BOT_TAG_PREFIX + tag)
  #end
  #
  #def remove_bot_tag(opp, tag)
  #  remove_tag(opp, BOT_TAG_PREFIX + tag)
  #end
  
end
