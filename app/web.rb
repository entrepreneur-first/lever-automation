require 'sinatra'
require_relative 'slack_authorizer'
require_relative 'bigquery'
require_relative 'client'

use SlackAuthorizer

HELP_RESPONSE = 'Use `/lever` to look up a candidate in Lever by name or email. Example: `/lever Dolly Parton` or `/lever dolly@parton.com`'.freeze

VALID_LOOKUP_EXPRESSION = /^(.+)/

OK_RESPONSE = "Looking up %s!".freeze

INVALID_RESPONSE = 'Sorry, I didn’t quite get that. This usually works: `/lever <name|email>`.'.freeze

@log = Log.new
@client = Client.new(ENV['LKEY'], @log)

post '/slack/command' do
  case params['text'].to_s.strip
  when 'help', '' then HELP_RESPONSE
  when VALID_LOOKUP_EXPRESSION then format_slack_response(find_opportunities(params['text']))
  else INVALID_RESPONSE
  end
end

def format_slack_response(matches)
  matches.map{|o| "#{o['name']} - #{o['urls']['show']}"}.join("\n")
end


def find_opportunities(search)
  search_esc = search.gsub("'", "\\\\'")
  
  b = BigQuery.new
  contacts = b.query("SELECT DISTINCT(contact) contact FROM #{b.table.query_id} WHERE name = '#{search_esc}' OR links LIKE '#{search_esc}' OR emails LIKE '#{search_esc}'", '')
  
  @client.get_paged_result(OPPORTUNITIES_URL, {contact_id: contacts, expand: client.OPP_EXPAND_VALUES}, 'opportunities_for_contact_ids')
end
