require 'sinatra'
require 'json'
require_relative 'slack_authorizer'
require_relative 'bigquery'
require_relative 'client'

use SlackAuthorizer

HELP_RESPONSE = 'Use `/lever` to look up a candidate in Lever by name or email. Example: `/lever Dolly Parton` or `/lever dolly@parton.com`'.freeze

VALID_LOOKUP_EXPRESSION = /^(.+)/

OK_RESPONSE = "Looking up %s!".freeze

INVALID_RESPONSE = 'Sorry, I didn’t quite get that. This usually works: `/lever <name|email>`.'.freeze

@controller = Controller.new

post '/slack/command' do
  content_type :json

  case params['text'].to_s.strip
  when 'help', '' then {
      'response_type': 'ephemeral',
      'text': HELP_RESPONSE
    }
  when VALID_LOOKUP_EXPRESSION then {
    'response_type': (params['command'].end_with?('me') ? 'ephemeral' : 'in_channel'),
    'text': format_slack_response(find_opportunities(params['text']))
  else {
      'response_type': 'ephemeral',
      'text': INVALID_RESPONSE
    }
  end
end
