# frozen_string_literal: true

# utility functions

class Util

  # common opportunity logic

  def self.opp_view_data(opp)
    recursive_add_datetime(
      opp.reject{|k,v| k.start_with?('_') || (k == 'applications')}.merge({
        application: opp['applications'][0],
        feedback_summary: parse_all_feedback_summary_link(opp),
        overall_source: overall_source_from_opp(opp),
        original_links: actual_links(opp),
        offered_at: (find_stage_changes(opp, OFFER_STAGES).first || {})['updatedAt'],
        offer_accepted_at: (find_stage_changes(opp, OFFER_ACCEPTED_STAGES).first || {})['updatedAt'],
        app_review_stage_at:(find_stage_changes(opp, APP_REVIEW_STAGES).first || {})['updatedAt'],
        phone_screen_stage_at:(find_stage_changes(opp, PHONE_SCREEN_STAGES).first || {})['updatedAt'],
        invite_to_interview_stage_at:(find_stage_changes(opp, INVITE_TO_INTERVIEW_STAGES).first || {})['updatedAt'],
        interview_stage_at:(find_stage_changes(opp, INTERVIEW_STAGES).first || {})['updatedAt'],
        exercise_stage_at:(find_stage_changes(opp, EXERCISE_STAGES).first || {})['updatedAt'],
        second_interview_stage_at:(find_stage_changes(opp, SECOND_INTERVIEW_STAGES).first || {})['updatedAt'],
        onsite_interview_stage_at:(find_stage_changes(opp, ONSITE_INTERVIEW_STAGES).first || {})['updatedAt'],
        final_interview_stage_at:(find_stage_changes(opp, FINAL_INTERVIEW_STAGES).first || {})['updatedAt'],
        to_archive_stage_at:(find_stage_changes(opp, TO_ARCHIVE_STAGES).first || {})['updatedAt'],
        started_cohort_stage_at:(find_stage_changes(opp, STARTED_COHORT_STAGES).first || {})['updatedAt']

      }))
  end
  
  def self.view_flat(opp)
    flatten_hash(opp_view_data(opp))
  end
  
  def self.recursive_add_datetime(h)
    h.keys.each { |k|
      if h[k].class == Hash
        recursive_add_datetime(h[k])
      elsif h[k].to_s.match?(/^[0-9]{10}$/)
        h[k.to_s + '__datetime'] = Time.at(h[k].to_i).strftime('%F %T')
      elsif h[k].to_s.match?(/^[0-9]{13}$/)
        h[k.to_s + '__datetime'] = Time.at(h[k].to_i/1000).strftime('%F %T')
      end
    }
    h
  end
  
  def self.overall_source_from_opp(opp)
    rules = Rules.new(nil)
    find_tag_value(opp, rules.tags(:source), TAG_OVERALL)
  end
  
  def self.find_tag_value(opp, tag_set, prefix)
    set_tags = tag_set.map{|k, v| prefix + v}
    opp['tags'].each { |tag|
      return tag.delete_prefix(prefix) if set_tags.include?(tag)
    }
    nil
  end
  
  def self.find_stage_changes(opp, stage_ids)
    (opp.dig('stageChanges') || []).select { |stage_change|
      Array(stage_ids).include?(stage_change['toStageId'])
    }
  end

  def self.parse_all_feedback_summary_link(opp)
    URI.decode_www_form((opp['links'].select {|l|
      l.start_with?(LINK_ALL_FEEDBACK_SUMMARY_PREFIX + cohort(opp) + '?')
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
  
  def self.posting(opp, none='none')
    opp.dig('applications', 0, 'posting') || none
  end
  
  def self.cohort(opp, unknown='unknown')
    posting_cohort(posting(opp)) || unknown
  end
  
  def self.posting_data(posting_id)
    COHORT_JOBS.select { |posting| posting[:posting_id] == posting_id }.first
  end

  def self.current_cohorts
    COHORT_JOBS.select { |posting| posting.has_key?(:tag) }
  end
  
  def self.posting_cohort(posting_id)
    (posting_data(posting_id) || {})[:cohort]
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

  def self.escape_sql(str)
    str.gsub("'", "\\\\'")
  end

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
  
  def self.lookup_row_fuzzy(array, search_val, search_key='id', result_key=nil)
    lookup_row(array, search_val, search_key, result_key, true)
  end
  
  def self.lookup_row(array, search_val, search_key='id', result_key=nil, fuzzy=false)
    search_val = fuzzy_string(search_val) if fuzzy
    array.each { |row|
      return result_key ? row[result_key] : row if (fuzzy ? fuzzy_string(row[search_key]) : row[search_key]) == search_val
    }
    nil
  end
  
  def self.get_hash_key_fuzzy(hash, key)
    get_hash_element_fuzzy(hash, key)[0]
  end
  
  def self.get_hash_value_fuzzy(hash, key)
    get_hash_element_fuzzy(hash, key)[1]
  end
  
  def self.get_hash_element_fuzzy(hash, key)
    key = fuzzy_string(key)
    hash.each { |k, v|
      v = v.strip if v.class == String
      return [k, v] if fuzzy_string(k) == key
    }
    [nil, nil]
  end
  
  def self.fuzzy_string(str)
    str.to_s.downcase.gsub(/[^a-z0-9]/, '')
  end
  
  def self.datetimestr_to_timestamp(d)
    DateTime.parse(d).strftime('%s').to_i*1000
  end
  
  def self.timestamp_to_datetimestr(t)
    Time.at((t/1000.0).ceil).utc.to_s
  end

  def self.simplify_str(str, also_allow_pattern='')
    str.downcase.gsub(/[^a-z0-9\-\/\s#{Regexp.quote(also_allow_pattern.to_s)}]/, '').gsub(/\s+/, ' ').strip
  end
  
  def self.log_if_api_error(log, result)
    # if not an error
    return if result.is_a?(NilClass) || is_http_success(result)
    # 404s are a valid API GET response
    return if result.request && (result.request.http_method == Net::HTTP::Get) && (result.code == 404)
    
    log.error((result.code.to_s || '') + ': ' + (result.parsed_response['code'] || '<no code>') + ': ' + (result.parsed_response['message'] || '<no message>'))
  end
  
  def self.is_http_success(result)
    result && result.code && result.code.between?(200, 299)
  end
  
  def self.is_http_error(result)
    !is_http_success(result)
  end  
end
