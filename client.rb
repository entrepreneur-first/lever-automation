# frozen_string_literal: true

require 'httparty'
require 'uri'

LEVER_BOT_USER = 'e6414a92-e785-46eb-ad30-181c18db19b5'
API_URL = 'https://api.lever.co/v1/'
OPPORTUNITIES_URL = API_URL + 'opportunities?'

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

  def authenticate
    result = HTTParty.get(OPPORTUNITIES_URL, basic_auth: auth)
    return result unless result.code == 200

    true
  end

  def all_opportunities(posting_ids = [])
    arr = []
    puts "Fetching opportunities"
    arr += opportunities(posting_ids)
    puts "Fetching archived opportuninites"
    arr += archived_opportunities(posting_ids)
    arr
  end

  def get_paged_result(url, params, log_string)
    arr = []
    result = HTTParty.get(url + to_query(params), basic_auth: auth)
    arr += result.fetch('data')
    page = 0
    while result.fetch('hasNext')
      next_batch = result.fetch('next')
      api_call_log(log_string, page) do
        result = HTTParty.get(url + to_query(params.merge(offset: next_batch)), basic_auth: auth)
      end
      arr += result.fetch('data')
      page += 1
    end
    arr
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

  private

  def add_candidate_to_posting(candidate_id, posting_id)
    puts "\nAdding candidate " + candidate_id + " to posting " + posting_id + ".."
    result = HTTParty.post(API_URL + 'candidates/' + candidate_id + '/addPostings?' + to_query({
        perform_as: LEVER_BOT_USER
      }),
      body: {
        postings: [posting_id]
      }.to_json,
      headers: { 'Content-Type' => 'application/json' },
      basic_auth: auth
    )
    result2 = HTTParty.post(API_URL + 'opportunities/' + candidate_id + '/addTags?' + to_query({
        perform_as: LEVER_BOT_USER
      }),
      body: {
        tags: ["x-auto-tagged-to-job"]
      }.to_json,
      headers: { 'Content-Type' => 'application/json' },
      basic_auth: auth
    )
    puts "done."
    result
  end

  def to_query(hash)
    URI.encode_www_form(BASE_PARAMS.merge(hash))
  end

  def auth
    { username: @username, password: @password }
  end

  def api_call_log(resource, page)
    puts "Lever API #{resource} page=#{page} start"
    yield
    puts "Lever API #{resource} page=#{page} end"
    true
  end

  def feedback_url(opportunity_id)
    API_URL + "opportunities/#{opportunity_id}/feedback"
  end
end
