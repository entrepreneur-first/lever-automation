# frozen_string_literal: true

require 'csv'

class Writer
  def initialize(filename, data)
    @filename = filename
    @data = data
  end

  def run
    CSV.open(@filename, 'w') do |csv|
      @data.each { |row| csv << row }
    end
  end
end
