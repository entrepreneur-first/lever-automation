require 'sinatra'
require 'json'
require 'httparty'
require_relative 'slack_authorizer'
require_relative 'bigquery'
require_relative '../controller/controller'

use SlackAuthorizer

HELP_RESPONSE = 'Use `/lever` to look up a candidate in Lever by name, email or link. Examples: `/lever Dolly Parton`, `/lever dolly@parton.com`, `/lever linkedin.com/in/dollyparton`'.freeze

VALID_LOOKUP_EXPRESSION = /^(.+)/

INVALID_RESPONSE = 'Sorry, I didn’t quite get that. This usually works: `/lever <name, email or url>`.'.freeze

controller = Controller.new

post '/slack/command' do
  content_type :json

  case params['text'].to_s.strip
  when 'help', '' then
    {
      'response_type': 'ephemeral',
      'text': HELP_RESPONSE
    }.to_json
    
  when VALID_LOOKUP_EXPRESSION then 
    p = fork {
      result = HTTParty.post(
        params['response_url'],
        body: {
          'response_type': (params['command'].end_with?('me') ? 'ephemeral' : 'in_channel'),
          'blocks': controller.slack_lookup(params)
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
    }
    Process.detach(p)
    
    result = {'text': "Searching Lever for candidates matching `#{params['text']}`.."}
    result['response_type'] = 'in_channel' unless params['command'].end_with?('me') 
    
    result.to_json
    
  else
    {
      'response_type': 'ephemeral',
      'text': INVALID_RESPONSE
    }.to_json
  end
end
