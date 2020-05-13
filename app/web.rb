require 'sinatra'
require 'json'
require_relative 'slack_authorizer'
require_relative 'bigquery'
require_relative '../controller/controller'

use SlackAuthorizer

HELP_RESPONSE = 'Use `/lever` to look up a candidate in Lever by name, email or link. Example: `/lever Dolly Parton`, `/lever dolly@parton.com`, `/lever linkedin.com/in/dollyparton`'.freeze

VALID_LOOKUP_EXPRESSION = /^(.+)/

OK_RESPONSE = "Looking up %s!".freeze

INVALID_RESPONSE = 'Sorry, I didn’t quite get that. This usually works: `/lever <name, email or url>`.'.freeze

@@controller = Controller.new

post '/slack/command' do
  content_type :json

  case params['text'].to_s.strip
  when 'help', '' then {
      'response_type': 'ephemeral',
      'text': HELP_RESPONSE
    }
  when VALID_LOOKUP_EXPRESSION then {
    'response_type': (params['command'].end_with?('me') ? 'ephemeral' : 'in_channel'),
    'text': @@controller.slack_lookup(params['text'])
  else {
      'response_type': 'ephemeral',
      'text': INVALID_RESPONSE
    }
  end
end
