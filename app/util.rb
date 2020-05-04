# frozen_string_literal: true

# utility functions

class Util

  # common lever logic

  def self.has_posting(opp)
    opp['applications'].any?
  end

  def self.has_application(opp)
    opp['applications'].any? &&
      opp['applications'][0]['type'] == 'posting' &&
      opp['applications'][0]['customQuestions'].any?
  end
  
  def self.is_cohort_app(opp)
    opp['tags'].include?(COHORT_JOB_TAG)
  end
  
  def self.is_archived(opp)
    !opp['archived'].nil? && (opp['archived']['archivedAt'] || 0) > 0
  end
  
  def self.actual_links(opp)
    opp['links'].reject{|l| l.start_with?(AUTO_LINK_PREFIX)}
  end

  def self.has_feedback(opp)
    opp['links'].select{|l| l.start_with?(AUTO_LINK_PREFIX + 'feedback/')}.any?
  end

  # generic util functions

  def self.to_query(hash)
    URI.encode_www_form(BASE_PARAMS.merge(hash))
  end

  def self.dup_hash(ary)
    ary.inject(Hash.new(0)) { |h,e| h[e] += 1; h }
      .select { |_k,v| v > 1 }
      .inject({}) { |r, e| r[e.first] = e.last; r }
  end
  
  def self.datetimestr_to_timestamp(d)
    DateTime.parse(d).strftime('%s').to_i*1000
  end
  
  def self.timestamp_to_datetimestr(t)
    Time.at((t/1000.0).ceil).utc.to_s
  end

  def self.simplify_str(str)
    str.downcase.gsub(/[^a-z0-9\-\/\s]/, '').gsub(/\s+/, ' ').strip
  end
end