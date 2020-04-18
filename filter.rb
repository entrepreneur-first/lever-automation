# frozen_string_literal: true

class Filter
  HEADERS = ['Candidate ID', 'Profile Name', 'Name on Application', 'Application Created At', 'Application Values', 'Application Name', 'Posting ID', 'Opportunity ID', 'Stage Index', 'Stage Text', 'Stage Times'].freeze

  def initialize(data)
    @data = data
  end

  def opportunities
    arr = @data.map { |opportunity| parse_opportunity(opportunity) }
    arr.unshift(HEADERS)
    arr
  end

  def feedback
    arr = @data.map { |f| parse_feedback(f) }
    arr.unshift(['Opportunity ID', 'Interview Type', 'Scorecard Completed At', 'Scorecard Values', 'Scorecard Submitted by'])
    arr
  end

  private

  def parse_feedback(f)
    [
      f.fetch('opportunity_id'),
      f.fetch('text'),
      Time.at(f.fetch('createdAt') / 1000).iso8601,
      f.fetch('fields').map { |field| field['value'] }.join(','),
      f.fetch('user')
    ]
  end

  def parse_opportunity(o)
    created_at = if o.fetch('applications').first&.fetch('createdAt')
                   Time.at(o.fetch('applications').first&.fetch('createdAt') / 1000)
                 else
                   ''
    end
    [
      o.fetch('contact'),
      o.fetch('name'),
      o.fetch('applications').first&.fetch('name'),
      created_at,
      (o.fetch('applications').first&.fetch('customQuestions')&.first&.fetch('fields') || []).map { |f| f['value'] }.join(','),
      o.fetch('applications').first&.fetch('customQuestions')&.first&.fetch('text'),
      o.fetch('applications').first&.fetch('posting'),
      o.fetch('id'),
      o.fetch('stageChanges').map { |change| change.fetch('toStageIndex') }.join(','),
      o.dig('stage', 'text'),
      o.fetch('stageChanges').map { |change| Time.at(change.fetch('updatedAt') / 1000).iso8601 }.join(',')
    ]
  end
end
