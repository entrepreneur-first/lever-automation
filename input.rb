# frozen_string_literal: true

require_relative 'client'

class Input
  attr_reader :api_key, :posting_ids

  def prompt
    puts "\nEnter Lever API key"
    @api_key = gets.chomp

    # puts "\nEnter posting IDs separated by comma: (e.g. XXX-XXX-XXX,YYY-YYY-YYY,...)"
    # @posting_ids = gets.chomp.split(',').map(&:strip)

    puts "\n"

    auth = Client.new(api_key).authenticate

    return if auth == true

    puts "\n Error: #{auth['code']} #{auth['message']}"
    exit
  end
end
