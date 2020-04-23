# frozen_string_literal: true

require "bundler/inline"
gemfile true do
  source "http://rubygems.org"
  gem "httparty"
end
require "date"
require "digest/md5"
require_relative "client"

client = Client.new(ENV['LKEY'])

loop do
  puts "\nEnter 'summarise', 'process', or email to process one candidate:"
  command = gets.chomp

  case command
  when ''
      break
      
  when 'summarise'
      client.summarise_opportunities
      
  when 'process'
      client.process_opportunities
      
  when 'fix tags'
      client.fix_auto_assigned_tags
  
  when 'check links'
      client.check_links

  else
    email = command.gsub('mailto:', '')
    command, email = command.split(' ') if command.include?(' ')
    os = client.opportunities_for_contact(email)
    case command
    when 'view'
      puts JSON.pretty_generate(os)
    else
      os.each { |opp| client.process_opportunity(opp) }
    end
  end
end

puts 'OK, bye'
