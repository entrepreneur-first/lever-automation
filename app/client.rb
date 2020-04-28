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

  def initialize(username, log)
    @username = username
    @password = ''
    @log = log
  end
  
  def log
    @log
  end

  #
  # Reading data
  #

  def get_opportunity(id, params={})
    get_single_result(OPPORTUNITIES_URL.chomp('?') + '/' + id, params, 'retrieve single opportunity')
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
  
  def feedback_for_opp(opp)
    get_paged_result(feedback_url(opp['id']), {}, 'feedback')
  end
  
  def feedback(opportunities_ids = [])
    arr = []
    total = opportunities_ids.count
    opportunities_ids.each_with_index.each do |opportunity_id, index|
      result = api_call_log('feedback', "#{index + 1}/#{total}") do
        HTTParty.get(feedback_url(opportunity_id), basic_auth: auth)
      end
      arr += result.fetch('data').map { |x| x.merge('opportunity_id' => opportunity_id) }
    end
    arr
  end

  #
  # Updating data
  #

  def batch_updates(batch=true)
    @batch_updates = batch
  end

  def commit_opp(opp)
    ['Tags','Links'].each{|type|
      add_annotations(opp, type, opp['_add'+type], true) if (opp['_add'+type] || []).any?
      remove_annotations(opp, type, opp['_remove'+type], true) if (opp['_remove'+type] || []).any?
    }
  end
  
  def add_tag(opp, tags, commit=false)
    add_annotations(opp, 'Tags', tags, commit)
  end
  
  def remove_tag(opp, tags, commit=false)
    remove_annotations(opp, 'Tags', tags, commit)
  end
  
  def remove_tags_with_prefix(opp, prefix)
    opp["tags"].each { |tag|
      remove_tag(opp, tag) if tag.start_with? prefix
    }
  end

  def add_links(opp, links, commit=false)
    add_annotations(opp, 'Links', links, commit)
  end
  
  def remove_links(opp, links, commit=false)
    remove_annotations(opp, 'Links', links, commit)
  end

  def remove_links_with_prefix(opp, prefix)
    opp["links"].each { |link|
      remove_links(opp, link) if link.start_with? prefix
    }
  end

  def add_annotations(opp, type, values, commit)  
    values = [values] if values.class != Array
    return queue_add_annotations(opp, type, values) if @batch_updates && !commit    
    ltype = type.downcase

    api_action_log("Adding #{ltype}: " + values.join(',')) do
      result = HTTParty.post(API_URL + 'opportunities/' + opp["id"] + "/add#{type}?" + Util.to_query({ perform_as: LEVER_BOT_USER }),
        body: {
          "#{ltype}": values
        }.to_json,
        headers: { 'Content-Type' => 'application/json' },
        basic_auth: auth
      )
      values.each {|value|
        opp[ltype] += [value] if !opp[ltype].include?(value)
      }
      result
    end
  end
  
  def remove_annotations(opp, type, values, commit=false)
    values = [values] if values.class != Array
    return queue_remove_annotations(opp, type, values) if @batch_updates && !commit
    ltype = type.downcase
    
    api_action_log("Removing #{ltype}: " + values.join(',')) do
      result = HTTParty.post(API_URL + 'opportunities/' + opp["id"] + "/remove#{type}?" + Util.to_query({ perform_as: LEVER_BOT_USER }),
        body: {
          "#{ltype}": values
        }.to_json,
        headers: { 'Content-Type' => 'application/json' },
        basic_auth: auth
      )
      values.each {|value|
        opp[ltype].delete(value)
      }
      result
    end
  end
    
  def queue_add_annotations(opp, type, values)
    values = [values] if values.class != Array
    ltype = type.downcase
    values.each { |value|
      opp['_add'+type] = [] if opp['_add'+type].nil?
      opp['_add'+type] << value unless opp['_add'+type].include?(value)
      opp[ltype] << value unless opp[ltype].include?(value)
      opp['_remove'+type].delete(value) unless opp['_remove'+type].nil?
    }
  end
  
  def queue_remove_annotations(opp, type, values)
    values = [values] if values.class != Array
    ltype = type.downcase
    values.each { |value|
      opp['_remove'+type] = [] if opp['_remove'+type].nil?
      opp['_remove'+type] << value unless opp['_remove'+type].include?(value) || (!opp['_add'+type].nil? && opp['_add'+type].include?(value))
      opp['_add'+type].delete(value) unless opp['_add'+type].nil?
      opp[ltype].delete(value)
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
    result = api_call_log(log_string, '<single>') do
      result = HTTParty.get(u, basic_auth: auth)
    end
    result.fetch('data')
  end
   
  def process_paged_result(url, params, log_string)
    page = 1
    next_batch = nil
    loop do
      result = api_call_log(log_string, page) do
        HTTParty.get(url + '?' + Util.to_query(params.merge(offset: next_batch).reject{|k,v| v.nil?}), basic_auth: auth)
      end
      result.fetch('data').each { |row| yield(row) }
      break unless result.fetch('hasNext')
      next_batch = result.fetch('next')
      page += 1
    end
  end

  def get_paged_result(url, params={}, log_string='')
    arr = []
    process_paged_result(url, params, log_string) { |row| arr << row }
    arr
  end  

  #
  # Wrappers for making API calls with logging
  #

  def api_call_log(resource, page)
    log.log("Lever API #{resource} page=#{page}") if log.verbose?
    result = yield
    log_if_api_error(result)
    result
  end

  def api_action_log(msg)
    log.log(msg)
    result = yield
    # retry on occasional bad gateway error
    if result.code == 502
      log.warn('502 error, retrying')
      result = yield
    end
    log_if_api_error(result)
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
  
  def log_if_api_error(result)
    # if not an error
    return if result.code.between?(200, 299)
    log.error((result.code.to_s || '') + ': ' + (result.parsed_response['code'] || '<no code>') + ': ' + (result.parsed_response['message'] || '<no message>'))
  end
end
