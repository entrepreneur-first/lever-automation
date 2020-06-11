# frozen_string_literal: true

require 'date'
require 'time'
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

class BadGatewayError < StandardError
end

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

  def opportunities_for_email(email)
    get_paged_result(OPPORTUNITIES_URL, {email: email, expand: self.OPP_EXPAND_VALUES}, 'opportunities_for_email')
  end

  def opportunities_for_contact(contact_ids)
    get_paged_result(OPPORTUNITIES_URL, {contact_id: contact_ids, expand: self.OPP_EXPAND_VALUES}, 'opportunities_for_contact')
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
  
  def profile_forms_for_opp(opp)
    get_paged_result(profile_forms_url(opp), {}, 'profile_forms')
  end
  
  def feedback(opportunities_ids = [])
    arr = []
    total = opportunities_ids.count
    opportunities_ids.each_with_index.each do |opportunity_id, index|
      result = api_call_log('feedback', "#{index + 1}/#{total}") do
        get(feedback_url(opportunity_id))
      end
      arr += result.fetch('data', []).map { |x| x.merge('opportunity_id' => opportunity_id) }
    end
    arr
  end
  
  def profile_form_template(id)
    get_single_result("#{API_URL}form_templates/#{id.class == Hash ?
      id['id'] : id}", {}, "get profile form: #{id}")
  end
  
  def users
    @users ||= get_paged_result("#{API_URL}users", {}, 'users')
    @users
  end

  def postings
    @postings ||= get_paged_result("#{API_URL}postings", {}, 'job postings')
    @postings
  end

  #
  # Updating data
  #

  def batch_updates(batch=true)
    prev = @batch_updates
    @batch_updates = batch
    prev
  end

  def commit_opp(opp, test_mode=false)
    updated = false
    ['Tags','Links'].each{ |type|
      if Array(opp['_add'+type]).any?
        add_annotations(opp, type, opp['_add'+type], !test_mode)
        opp['_add'+type] = []
        updated = true
      end
      if Array(opp['_remove'+type]).any?
        remove_annotations(opp, type, opp['_remove'+type], !test_mode)
        opp['_remove'+type] = []
        updated = true
      end
    }
    updated
  end
  
  def refresh_opp(opp)
    opp.merge!(get_opportunity(opp['id'], {expand: self.OPP_EXPAND_VALUES}))
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
    opps = opportunities_for_email(email)
    opps_without_posting = opps.select { |o| o["applications"].count == 0 }
    
    result = []
    opps_without_posting.each { |o|
      result += add_candidate_to_posting(o["id"], posting_id)
    }
    result
  end

  def add_candidate_to_posting(candidate_id, posting_id)
    api_action_log("Adding to posting " + posting_id) do
      post(
        API_URL + 'candidates/' + candidate_id + '/addPostings?',
        {postings: [posting_id]}
      )
    end
  end

  def archive(opp, reason=nil)
    reason ||= '4e68ea29-9277-47a2-b48d-8e2b2d875638' # default archive reason: duplicate
    api_action_log('Archiving opportunity with reason: ' + reason) do
      put("#{opp_url(opp)}/archived?", {reason: reason})
    end
  end

  def update_stage(opp, stage_id)
    api_action_log('Moving opportunity to stage: ' + stage_id) do
      put("#{opp_url(opp)}/stage?", {stage: stage_id})
    end
  end

  def prepare_feedback(template_id, fields)
    form = profile_form_template(template_id)
    fields_data = form['fields']
    fields = fields.transform_keys(&:to_s)
    
    keys_found = []
    fields_data.map!{ |field|
      key, val = Util.get_hash_element_fuzzy(fields, field['text'])
      keys_found << key unless key.nil?
      val = val.to_s
      if ['createdAt', 'completedAt'].include?(field['text']) && !val.match?(/^[0-9]*$/)
        val = (Time.parse(val).to_i*1000).to_s
      end
      if field['text'] == 'user' && !val.match(/^[0-9a-z\-]{30,}$/)
        lookup_val = Util.lookup_row_fuzzy(users, val, 'name', 'id')
        if lookup_val.nil?
          log.warn("User not found: #{val}")
        else
          val = lookup_val
        end
      end
      field.merge({'value' => key.nil? ? '' : val})
    }
    
    {
      fields: fields_data,
      keys: keys_found
    }
  end

  def add_profile_form(opp, template_id, fields)
    api_action_log("Adding profile form for template: " + template_id) do
      result = post("#{opp_url(opp)}/forms?", {
        baseTemplateId: template_id,
        fields: fields
      })
      result
    end
  end

  def create_opportunity(params)
    api_action_log("Creating opportunity: {emails: #{(params[:emails] || []).join(',')}; links: #{(params[:links] || []).join(',')}}") do
      result = post("#{API_URL}/opportunities?perform_as_posting_owner=true&", params)
      result
    end
  end

  #
  # Helpers
  #
  
  def get_single_result(url, params={}, log_string='')
    api_call_log(log_string, '<single>') do
      get(url + '?' + Util.to_query(params))
    end.fetch('data', nil)
  end
   
  def process_paged_result(url, params, log_string=nil)
    page = 1
    next_batch = nil
    loop do
      result = api_call_log(log_string, page) do
        get(url + '?' + Util.to_query(params.merge(offset: next_batch).reject{|k,v| v.nil?}))
      end
      result.fetch('data', []).each { |row|
        yield(row)
      }
      break unless result.fetch('hasNext', nil)
      next_batch = result.fetch('next')
      page += 1
    end
  end

  def get_paged_result(url, params={}, log_string='')
    arr = []
    process_paged_result(url, params, log_string) { |row| arr << row }
    arr
  end
  
  def get(url)
    http_method(self.method(:_get).curry, url)
  end
  
  def post(url, body)
    http_method(self.method(:_post).curry, url, body)
  end
  
  def put(url, body)
    log.log("PUT: #{url}") if log.verbose?
    http_method(self.method(:_put).curry, url, body)
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
    yield
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
    begin
      result = method.(url, body)
      # retry on occasional bad gateway error
      raise BadGatewayError if result.code == 502
    rescue BadGatewayError, Net::OpenTimeout, EOFError, Errno::ECONNRESET => e
      if e.is_a?(BadGatewayError)
        log.warn("502 error, retrying")
      elsif e.is_a?(Net::OpenTimeout)
        log.warn("Net::OpenTimeout error, retrying")
      elsif e.is_a?(EOFError)
        log.warn("EOFError, retrying")
      elsif e.is_a?(Errno::ECONNRESET)
        log.warn("Errno::ECONNRESET, retrying")
      else
        log.error("http_method: unknown error occurred: #{e}")
      end
      begin
        result = method.(url, body)
      rescue BadGatewayError, Net::OpenTimeout, EOFError, Errno::ECONNRESET => e
        if e.is_a?(BadGatewayError)
          log.warn("502 error on 2nd attempt; aborting")
        elsif e.is_a?(Net::OpenTimeout)
          log.warn("Net::OpenTimeout on 2nd attempt; aborting")
        elsif e.is_a?(EOFError)
          log.warn("EOFError on 2nd attempt; aborting")
        elsif e.is_a?(Errno::ECONNRESET)
          log.warn("Errno::ECONNRESET on 2nd attempt; aborting")
        else
          log.error("http_method: unknown error occurred on 2nd attempt: #{e}")
        end
      end
    end
    Util.log_if_api_error(log, result)
    result.parsed_response if result && result.respond_to?(:parsed_response)
  end
  
  def _get(url, _ignore_body)
    HTTParty.get(url, basic_auth: auth)
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

  def profile_forms_url(opp)
    "#{opp_url(opp)}/forms"
  end
end
