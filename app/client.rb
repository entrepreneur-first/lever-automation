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
  
  def OPP_EXPAND_VALUES
    ['applications', 'stage','sourcedBy','owner']
  end

  #
  # Reading data
  #

  def get_opportunity(id, params={})
    get_single_result(opp_url(id), params, 'retrieve single opportunity')
  end

  def opportunities_for_contact(email)
    get_paged_result(OPPORTUNITIES_URL, {email: email, expand: self.OPP_EXPAND_VALUES}, 'opportunities_for_contact')
  end

  def opportunities(posting_ids = [], params = {})
    get_paged_result(OPPORTUNITIES_URL, OPPORTUNITIES_PARAMS.merge(posting_id: posting_ids).merge(params), 'opportunities')
  end

  def archived_opportunities(posting_ids = [])
    get_paged_result(OPPORTUNITIES_URL, OPPORTUNITIES_PARAMS.merge(archived_posting_id: posting_ids), 'archived_opportunities')
  end

  def all_opportunities(posting_ids = [])
    opportunities(posting_ids) + archived_opportunities(posting_ids)
  end
  
  def feedback_for_opp(opp)
    get_paged_result(feedback_url(opp), {}, 'feedback')
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
    updated = false
    ['Tags','Links'].each{|type|
      (updated = true; add_annotations(opp, type, opp['_add'+type], true)) if Array(opp['_add'+type]).any?
      (updated = true; remove_annotations(opp, type, opp['_remove'+type], true)) if Array(opp['_remove'+type]).any?
    }
    updated
  end
  
  def add_tag(opp, tags, commit=false)
    add_annotations(opp, 'Tags', tags, commit)
  end
  
  def add_tags_if_unset(opp, tags, commit=false)
    add_annotations(opp, 'Tags', Array(tags).reject {|t| opp['tags'].include? t}, commit)
  end
  
  def remove_tag(opp, tags, commit=false)
    remove_annotations(opp, 'Tags', tags, commit)
  end
  
  def remove_tags_if_set(opp, tags, commit=false)
    remove_annotations(opp, 'Tags', Array(tags).select {|t| opp['tags'].include? t}, commit)
  end
  
  def remove_tags_with_prefix(opp, prefix)
    opp["tags"].clone.each { |tag|
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
    opp["links"].clone.each { |link|
      remove_links(opp, link) if link.start_with? prefix
    }
  end

  def add_annotations(opp, type, values, commit)
    values = Array(values)
    return if !values.any?
    return queue_add_annotations(opp, type, values) if @batch_updates && !commit    
    ltype = type.downcase

    api_action_log("Adding #{ltype}: " + values.join(',')) do
      result = post("#{opp_url(opp)}/add#{type}?", {"#{ltype}": values})
      values.each {|value|
        opp[ltype] += [value] if !opp[ltype].include?(value)
      }
      result
    end
  end
  
  def remove_annotations(opp, type, values, commit=false)
    values = Array(values)
    return if !values.any?
    return queue_remove_annotations(opp, type, values) if @batch_updates && !commit
    ltype = type.downcase
    
    api_action_log("Remove #{ltype}: " + values.join(',')) do
      result = post("#{opp_url(opp)}/remove#{type}?", {"#{ltype}": values})
      values.each {|value|
        opp[ltype].delete(value)
      }
      result
    end
  end
    
  def queue_add_annotations(opp, type, values)
    values = Array(values)
    ltype = type.downcase
    values.each { |value|
      opp['_add'+type] = [] if opp['_add'+type].nil?
      opp['_add'+type] << value unless opp['_add'+type].include?(value)
      opp[ltype] << value unless opp[ltype].include?(value)
      opp['_remove'+type].delete(value) unless opp['_remove'+type].nil?
    }
  end
  
  def queue_remove_annotations(opp, type, values)
    values = Array(values)
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
      result = post("#{opp_url(opp)}/notes?", {value: msg, createdAt: timestamp}.reject {|k,v| v.nil?})
      # record that we have left a note, since this will update the lastInteractionAt timestamp
      # so we should update our LAST_CHANGE_TAG
      opp['_addedNoteTimestamp'] = [
        opp['_addedNoteTimestamp'] || 0,
        timestamp || get_opportunity(opp['id']).fetch('lastInteractionAt', Time.now.to_i*1000)
      ].max
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
    result
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

  def archive(opp, reason=nil)
    reason ||= '' # default archive reason: 
    api_action_log('Archiving opportunity with reason: ' + reason) do
      put("#{opp_url(opp)}/archived?", {reason: reason})
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
    return nil if is_http_error(result)
    result.fetch('data')
  end
   
  def process_paged_result(url, params, log_string=nil)
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
  
  def post(url, body)
    http_method(self.method(:_post).curry, url, body)
  end
  
  def put(url, body)
    log.log("PUT: #{url}") if log.verbose?
    http_method(self.method(:_put).currt, url, body)
  end
  
  def delete(url)
    log.log("DELETE: #{url}") if log.verbose?
    http_method(self.method(:_delete).curry, url)
  end
  
  #
  # Wrappers for making API calls with logging
  #

  def api_call_log(resource, page)
    log.log("Lever API #{resource} page=#{page}") if log.verbose? && !resource.nil?
    result = yield
    log_if_api_error(result)
    result
  end

  def api_action_log(msg)
    log.log(msg) unless msg.nil?
    result = yield
  end

  def opp_url(opp)
    "#{API_URL}opportunities/#{opp.class == Hash ?
      opp['id'] : opp}"
  end

  #
  private
  #

  def http_method(method, url, body={})
    result = method.(url, body)
    # retry on occasional bad gateway error
    if result.code == 502
      log.warn('502 error, retrying')
      result = method.(url, body)
    end
    log_if_api_error(result)
    result.parsed_response
  end
  
  def _post(url, body)
    HTTParty.post(url + Util.to_query({
        perform_as: LEVER_BOT_USER
      }),
      body: body.to_json,
      headers: {'Content-Type' => 'application/json'},
      basic_auth: auth
    )
  end
  
  def _put(url, body)
    HTTParty.put(url + Util.to_query({
        perform_as: LEVER_BOT_USER
      }),
      body: body.to_json,
      headers: {'Content-Type' => 'application/json'},
      basic_auth: auth
    )
  end

  def _delete(url, body=nil)
    HTTParty.delete(url, basic_auth: auth)
  end

  def auth
    { username: @username, password: @password }
  end
  
  def feedback_url(opp)
    "#{opp_url(opp)}/feedback"
  end
  
  def log_if_api_error(result)
    # if not an error
    return if is_http_success(result)
    log.error((result.code.to_s || '') + ': ' + (result.parsed_response['code'] || '<no code>') + ': ' + (result.parsed_response['message'] || '<no message>'))
  end
  
  def is_http_success(result)
    result.code.between?(200, 299)
  end
  
  def is_http_error(result)
    !is_http_success(result)
  end
end
