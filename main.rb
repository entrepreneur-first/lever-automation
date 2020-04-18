# frozen_string_literal: true

require "bundler/inline"

gemfile true do
  source "http://rubygems.org"
  gem "httparty"
end

require_relative "client"
require_relative "filter"
require_relative "writer"
require_relative "input"

input = Input.new
input.prompt

client = Client.new(input.api_key)

 puts "\nEnter email:"
 email = gets.chomp
# posting_id = "23bf8c07-b32e-483f-9007-1b9c2a004eb6"
# client.assign_to_job(email, posting_id)

puts JSON.pretty_generate(client.opportunities_for_contact(email))

# client.opportunities_without_posting

# Opportunities

# raw_opportunities = Client.new(input.api_key).all_opportunities(input.posting_ids)
# puts raw_opportunities.count
# filtered_opportunities = Filter.new(raw_opportunities).opportunities
# Writer.new("opportunities.csv", filtered_opportunities).run

# Feedback

# opportunities_ids = raw_opportunities.map { |opp| opp.fetch("id") }
# raw_feedback = Client.new(input.api_key).feedback(opportunities_ids)
# filtered_feedback = Filter.new(raw_feedback).feedback
# Writer.new("feedback.csv", filtered_feedback).run
