# frozen_string_literal: true

# utility functions

class Util

  # common opportunity logic

  def self.opp_view_data(opp)
    recursive_add_datetime(
      opp.reject{|k,v| k.start_with?('_') || (k == 'applications')}.merge({
        application: opp['applications'][0],
        feedback_summary: parse_all_feedback_summary_link(opp)
      }))
  end
  
  def self.recursive_add_datetime(h)
    h.keys.each { |k|
      if h[k].class == Hash
        recursive_add_datetime(h[k])
      elsif h[k].to_s.match?(/^[0-9]{10}$/)
        h[k + '__datetime'] = Time.at(h[k].to_i).strftime('%F %T')
      elsif h[k].to_s.match?(/^[0-9]{13}$/)
        h[k + '__datetime'] = Time.at(h[k].to_i/1000).strftime('%F %T')
      end
    }
    h
  end

  def self.parse_all_feedback_summary_link(opp)
    URI.decode_www_form((opp['links'].select {|l|
      l.start_with?(LINK_ALL_FEEDBACK_SUMMARY_PREFIX)
    }.first || '').sub(/[^?]*\?/, '')).to_h
  end
  
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
  
  def self.flatten_hash(hash, to_hash={}, key_prefix='')
    hash.each { |k,v|
      if v.class == Hash
        flatten_hash(v, to_hash, key_prefix + k.to_s + '__')
      elsif v.class == Array
        to_hash[key_prefix + k.to_s] = v.join(v.all?{|e| e.class == String} ? ',' : "\n")
      else
        to_hash[key_prefix + k.to_s] = v
      end
    }
    to_hash
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
  
  def self.log_if_api_error(log, result)
    # if not an error
    return if is_http_success(result)
    log.error((result.code.to_s || '') + ': ' + (result.parsed_response['code'] || '<no code>') + ': ' + (result.parsed_response['message'] || '<no message>'))
  end
  
  def self.is_http_success(result)
    result.code.between?(200, 299)
  end
  
  def self.is_http_error(result)
    !is_http_success(result)
  end  
end
