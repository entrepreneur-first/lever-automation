# frozen_string_literal: true
require_relative '../app/base_rules.rb'

#
# Logic for rules we wish to apply
#

TAG_OVERALL = AUTO_TAG_PREFIX + 'Overall: '
TAG_ORIGINAL_OVERALL_PREFIX = TAG_ORIGINAL_PREFIX + (TAG_OVERALL.delete_prefix(AUTO_TAG_PREFIX))
TAG_HISTORIC_OVERALL_PREFIX = TAG_HISTORIC_PREFIX + (TAG_OVERALL.delete_prefix(AUTO_TAG_PREFIX))

TAG_FROM_APPLICATION = AUTO_TAG_PREFIX + 'App: '

TAG_FROM_PRE_SCREEN = AUTO_TAG_PREFIX + 'Pre-Screen: '
TAG_FROM_COFFEE = AUTO_TAG_PREFIX + 'Coffee: '
TAG_FROM_APP_REVIEW = AUTO_TAG_PREFIX + 'App Review: '
TAG_FROM_PHONE_SCREEN = AUTO_TAG_PREFIX + 'Phone Screen: '
TAG_FROM_F2F = AUTO_TAG_PREFIX + 'F2F: '
TAG_FROM_ABILITY_INTERVIEW = AUTO_TAG_PREFIX + 'Ability: '
TAG_FROM_BEHAVIOUR_INTERVIEW = AUTO_TAG_PREFIX + 'Behaviour: '
TAG_FROM_DEBRIEF = AUTO_TAG_PREFIX + 'Debrief: '

class Rules < BaseRules

  # list of tags for each category, so we can remove when updating with new values
  def all_tags
    {
      source: {
        sourced: 'Sourced',
        referral: 'Referral',
        organic: 'Organic',
        offline: 'Offline',
        digital_marketing: 'DM',
        rollover: 'Rollover',
        offline_organic: 'Offline-or-Organic',
        error: '<source unknown>'
      },
      gender: {
        female: 'Female',
        male: 'Male',
        other: 'Other',
        prefer_not_say: 'Gender: Prefer not to say',
        error: '<gender unknown>'
      },
      rating: {
        _4: '4 - Strong Hire',
        _3: '3 - Hire',
        _2: '2 - No Hire',
        _1: '1 - Strong No Hire',
        error: '<rating unknown>'
      },
      edge: {
        technical: 'Technical',
        domain: 'Domain',
        cat_talker: 'Catalyst Talker',
        cat_doer: 'Catalyst Doer',
        no_edge: 'No edge',
        error: '<edge unknown>'
      },
      eligibility: {
        eligible: 'Eligible',
        ineligible: 'Ineligible',
        error: '<eligibility unknown>'
      },
      availability: {
        available: 'Available',
        unavailable: 'Unavailable',
        error: '<availability unknown>'
      },
      software_hardware: {
        software: 'Software',
        hardware: 'Hardware',
        error: '<soft/hardware unknown>'
      },
      talker_doer: {
        talker: 'Talker',
        doer: 'Doer',
        both: 'Talker/Doer',
        neither: 'TD-Neither',
        unsure: 'TD-Unsure',
        error: '<talker/doer unknown>'
      },
      ceo_cto: {
        ceo: 'CEO',
        cto: 'CTO',
        error: '<ceo/cto unknown>'
      },
      new_ceo_cto: {
        ceo: 'CEO',
        cto: 'CTO',
        error: '<ceo/cto unknown>'
      },
      both_ceo_cto: {
        both: 'both',
        not_both: 'not_both',
        error: '<ceo/cto both unknown>'
      },
      visa_exposure: {
        yes: 'Visa Exposure',
        no: 'No Visa Exposure',
        error: '<visa exposure unknown>'
      },
      healthcare: {
        yes: 'Healthcare',
        no: 'Not Healthcare',
        error: '<healthcare unknown>'
      },
      
      duplicate_opps: {
        general: 'General opportunity',
        single: 'Single posting',
        single_plus_general: 'Single posting + general opp',
        multiple: 'Multiple postings'
      }
    }
  end

  def update_links(opp)
    opp(opp)
    links = []
    responses = opp['_app_responses']
    responses.each {|qu|
      if qu[:_text].include?('url') || qu[:_text].include?('links')
        next if qu[:_text].include?('who is')
        new_links = qu['value'].scan(/[^\s]+\.[^\s]+/)
        next unless new_links.any?
        links += new_links
        log.log("Added links from app field '#{qu[:_text]}': " + new_links.join(', '))
      end
    }
    add_links(links.uniq)
  end
  
  def summarise_one_feedback(f, opp)
    # don't summarise feedback if we have a new cohort not yet in config.rb
    return {} if Util.cohort(opp, nil).nil?
  
    result = {
      'cohort' => Util.cohort(opp)
    }

    # feedback type
    type = Util.simplify_str(f['text'])
    result['title'] = type
    result['type'] =
      if type.include?('coffee') || type.include?('initial call') || type.include?('london call') || type.include?('berlin call') || type.include?('paris call') || type.include?('toronto call') || type.include?('sy stream stage 4') || type.include?('prospect call')
        'coffee'
      elsif type.include?('sy stream phone screen') || type.include?('sy stream pi')
        'pre_coffee_screen'
      elsif type.include?('phone screen') # excludes 'sy stream phone screen' above
        'phone_screen'
      elsif type.include?('app review')
        'app_review'
      elsif type.include?('interview debrief')
        'debrief'
      elsif type.include?('ability')
        'ability_interview'
      elsif type.include?('behaviour')
        'behaviour_interview'
      else
        'unknown'
      end
    
    # rating
    # always one field of type 'score-system' for overall feedback rating
    result['rating'] = (f['fields'].select{|f| f['type'] == 'score-system'}.first || {})[:_value]
    # for imported feedback forms where all fields are strings, fall back to field name
    result['rating'] ||= (f['fields'].select{|f| f[:_text] == 'rating'}.first || {})[:_value].to_s
    result['rating'] = case result['rating']
      when '1'
        '1 - Strong No Hire'
      when '2'
        '2 - No Hire'
      when '3'
        '3 - Hire'
      when '4'
        '4 - Strong Hire'
      else
        result['rating']
      end
    
    if ['pre_coffee_screen', 'coffee'].include?(result['type'])
      # gender
      result['gender'] = (f['fields'].select{|f| f[:_text] == 'gender'}.first || {})[:_value]
      
      # eligibile
      cohort = (COHORT_JOBS.select { |j| j[:posting_id] == Util.posting(opp) }.first || {}).dig(:cohort)
      eligibility_value = (f['fields'].select { |f|
        f[:_text].include?('are they eligible') ||
        f[:_text].include?('elligible') ||
        f[:_text].include?('cohort they can join') ||
        f[:_text].include?('cohort they are') ||
        f[:_text] == 'eligible'  
      }.first || {})[:_value]
      result['eligible'] = if eligibility_value == 'yes'
          'eligible'
        elsif eligibility_value == 'no'
          'ineligible'
        elsif cohort.nil? || eligibility_value.nil?
          nil # unknown
        elsif (eligibility_value + ' ').include?(cohort.downcase + ' ')
          'eligible'
        else
          'ineligible'
        end
    
      # available
      availability_value = (f['fields'].select { |f|
        f[:_text].include?('available to join the cohort')
      }.first || {})[:_value]
      result['available'] = if availability_value == 'yes'
          'available'
        elsif availability_value.nil?
          nil # availability question does not exist for old coffee feedback forms
        elsif availability_value == 'no' || availability_value.include?('no - ')
          'unavailable'
        else
          nil # unknown
        end
    end
    
    if ['app_review', 'ability_interview'].include? result['type']
      # CEO / CTO
      result['ceo_cto'] = if type.include? 'ceo'
          'ceo'
        elsif type.include? 'cto'
          'cto'
        else
          'unknown'
        end
    end
    
    if ['app_review', 'debrief'].include?(result['type'])
      # talker/doer
      # TODO: question?
      result['talker_doer'] = (f['fields'].select{|f| f[:_text].include?('talker')}.first || {})[:_value]

      # industry
      # TODO: question?
      result['industry'] = (f['fields'].select{|f| f[:_text] == 'industry'}.first || {})[:_value]

      # industry
      # TODO: question?
      result['technology'] = (f['fields'].select{|f| f[:_text] == 'technology'}.first || {})[:_value]
      
      # ceo_cto_both
      both_value = (f['fields'].select{|f| f[:_text].include?('can this person potentially be both')}.first || {})[:_value]
      result['both_ceo_cto'] = if both_value == 'yes'
          'both'
        elsif both_value == 'no'
          'not_both'
         elsif both_value.nil?
          nil # unknown
        end
    end    
    
    if ['pre_coffee_screen', 'coffee', 'app_review', 'debrief'].include?(result['type'])
      # edge
      # TODO: question title varies
      result['edge'] = (f['fields'].select{|f| f[:_text].include?('edge')}.first || {})[:_value]

      # software/hardware
      # TODO: question?
      result['software_hardware'] = (f['fields'].select{|f| f[:_text].include?('software')}.first || {})[:_value]
    end
    
    if result['type'] == 'debrief'
      # healthcare
      # TODO: question?
      result['healthcare'] = (f['fields'].select{|f| f[:_text] == 'healthcare'}.first || {})[:_value]

      # visa exposure
      # TODO: question?
      result['visa_exposure'] = (f['fields'].select{|f| f[:_text] == 'visa exposure'}.first || {})[:_value]
      
      # new ceo/cto
       
      ceo_cto_value = (f['fields'].select{|f| f[:_text] == 'ceo or cto'}.first || {})[:_value]
      result['new_ceo_cto'] = if ceo_cto_value == 'ceo'
          'ceo'
        elsif ceo_cto_value == 'cto'
          'cto'
        elsif ceo_cto_value.nil?
          nil # unknown
        end


    end
        
    # when scorecard was completed
    result['submitted_at'] = f['completedAt']
    # scorecard submitted by
    result['submitted_by'] = f['user']
    
    result
  end

  def summarise_all_feedback(summaries, opp)
    # We store feedback summaries within Lever as links on the candidate contact
    # Links are shared across all opportunities for that candidate contact
    # so here we filter down to just feedback for the same cohort as the current opportunity
    summaries.select! { |f| f['cohort'] == Util.cohort(opp) }

    return {} unless summaries.any?
  
    result = {
      has_pre_coffee_screen: false,
      pre_coffee_screen_rating: nil,
      pre_coffee_screen_edge: nil,
      pre_coffee_screen_gender: nil,
      pre_coffee_screen_eligible: nil,
      pre_coffee_screen_software_hardware: nil,
      pre_coffee_screen_completed_at: nil,
      pre_coffee_screen_completed_by: nil,

      has_coffee: false,
      coffee_rating: nil,
      coffee_edge: nil,
      coffee_gender: nil,
      coffee_eligible: nil,
      coffee_available: nil,
      coffee_completed_at: nil,
      coffee_completed_by: nil,
      coffee_software_hardware: nil,

      has_app_review: false,
      app_review_rating: nil,
      app_review_edge: nil,
      app_review_software_hardware: nil,
      app_review_talker_doer: nil,
      app_review_industry: nil,
      app_review_technology: nil,
      app_review_ceo_cto: nil,
      app_review_completed_at: nil,
      app_review_completed_by: nil,
      app_review_both_ceo_cto: nil,
      
      has_phone_screen: false,
      phone_screen_rating: nil,
      phone_screen_completed_at: nil,
      phone_screen_completed_by: nil,
      
      has_ability: false,
      ability_rating: nil,
      f2f_ceo_cto: nil,
      ability_completed_at: nil,
      ability_completed_by: nil,
      
      has_behaviour: false,
      behaviour_rating: nil,
      behaviour_completed_at: nil,
      behaviour_completed_by: nil,
      
      has_debrief: false,
      debrief_rating: nil,
      debrief_completed_at: nil,
      debrief_edge: nil,
      debrief_software_hardware: nil,
      debrief_talker_doer: nil,
      debrief_industry: nil,
      debrief_technology: nil,
      debrief_healthcare: nil,
      debrief_visa_exposure: nil,
      debrief_ceo_cto: nil,
      debrief_both_ceo_cto: nil
    }
    
    summaries.sort_by{|f| f['submitted_at'] || ''}.each {|f|
      case f['type']
      when 'pre_coffee_screen'
        result[:has_pre_coffee_screen] = true
        result[:pre_coffee_screen_rating] = f['rating']
        result[:pre_coffee_screen_edge] = f['edge']
        result[:pre_coffee_screen_gender] = f['gender']
        result[:pre_coffee_screen_eligible] = f['eligible']
        result[:pre_coffee_screen_software_hardware] = f['software_hardware']
        result[:pre_coffee_screen_completed_at] = f['submitted_at']
        result[:pre_coffee_screen_completed_by] = f['submitted_by']
        
      when 'coffee'
        result[:has_coffee] = true
        result[:coffee_rating] = f['rating']
        result[:coffee_edge] = f['edge']
        result[:coffee_gender] = f['gender']
        result[:coffee_eligible] = f['eligible']
        result[:coffee_available] = f['available']
        result[:coffee_completed_at] = f['submitted_at']
        result[:coffee_completed_by] = f['submitted_by']
        result[:coffee_software_hardware] = f['software_hardware']
        
      when 'app_review'
        result[:has_app_review] = true
        result[:app_review_rating] = f['rating']
        result[:app_review_edge] = f['edge']
        result[:app_review_software_hardware] = f['software_hardware']
        result[:app_review_talker_doer] = f['talker_doer']
        result[:app_review_industry] = f['industry']
        result[:app_review_technology] = f['technology']
        result[:app_review_ceo_cto] = f['ceo_cto']
        result[:app_review_completed_at] = f['submitted_at']
        result[:app_review_completed_by] = f['submitted_by']
        result[:app_review_both_ceo_cto] = f['both_ceo_cto']
        
      when 'phone_screen'
        result[:has_phone_screen] = true
        result[:phone_screen_rating] = f['rating']
        result[:phone_screen_completed_at] = f['submitted_at']
        result[:phone_screen_completed_by] = f['submitted_by']

      when 'ability_interview'
        result[:has_ability] = true
        result[:ability_rating] = f['rating']
        result[:f2f_ceo_cto] = f['ceo_cto']
        result[:ability_completed_at] = f['submitted_at']
        result[:ability_completed_by] = f['submitted_by']
        
      when 'behaviour_interview'
        result[:has_behaviour] = true
        result[:behaviour_rating] = f['rating']
        result[:behaviour_completed_at] = f['submitted_at']
        result[:behaviour_completed_by] = f['submitted_by']
        
      when 'debrief'
        result[:has_debrief] = true
        result[:debrief_edge] = f['edge']
        result[:debrief_software_hardware] = f['software_hardware']
        result[:debrief_talker_doer] = f['talker_doer']
        result[:debrief_industry] = f['industry']
        result[:debrief_technology] = f['technology']
        result[:debrief_healthcare] = f['healthcare']
        result[:debrief_visa_exposure] = f['visa_exposure']
        result[:debrief_rating] = f['rating']
        result[:debrief_completed_at] = f['submitted_at']
        result[:debrief_ceo_cto] = f['new_ceo_cto']
        result[:debrief_both_ceo_cto] = f['both_ceo_cto']
      end
    }
    
    # legacy fix for hardware/software tags
    if (opp['tags'] & ['Software', 'Hardware']).any?
      value = opp['tags'].include?('Software') ? 'software' : 'hardware'
      # set value for most feedback form if not already present
      if result[:has_app_review]
        result[:app_review_software_hardware] ||= value
      elsif result[:has_coffee]
        result[:coffee_software_hardware] ||= value
      elsif result[:has_pre_coffee_screen]
        result[:pre_coffee_screen_software_hardware] ||= value
      end
    end
    
    result
  end

  def update_tags(opp, feedback_summary)
    @feedback_summary = feedback_summary

    # tags from application
    if Util.has_application(opp) && Util.is_cohort_app(opp)
      # automatically add tag for the opportunity source based on self-reported data in the application
      apply_single_tag(TAG_FROM_APPLICATION, source_from_app(opp), tags(:source))
      
      apply_single_tag(TAG_FROM_APPLICATION, gender_from_app(opp), tags(:gender))
    end
    
    # "master" source
    apply_single_tag(TAG_OVERALL, {tag: overall_source(opp)}, tags(:source))
    
    # feedback
    apply_feedback_tag(TAG_FROM_PRE_SCREEN, :pre_coffee_screen_rating, :rating, :has_pre_coffee_screen)
    apply_feedback_tag(TAG_FROM_PRE_SCREEN, :pre_coffee_screen_eligible, :eligibility, :has_pre_coffee_screen)
    
    apply_feedback_tag(TAG_FROM_COFFEE, :coffee_rating, :rating, :has_coffee)
    apply_feedback_tag(TAG_FROM_COFFEE, :coffee_edge, :edge, :has_coffee)
    apply_feedback_tag(TAG_FROM_COFFEE, :coffee_gender, :gender, :has_coffee)
    apply_feedback_tag(TAG_FROM_COFFEE, :coffee_eligible, :eligibility, :has_coffee)
    apply_feedback_tag(TAG_FROM_COFFEE, :coffee_available, :availability, :has_coffee)

    apply_feedback_tag(TAG_FROM_APP_REVIEW, :app_review_rating, :rating, :has_app_review)
    apply_feedback_tag(TAG_FROM_APP_REVIEW, :app_review_edge, :edge, :has_app_review)
    apply_feedback_tag(TAG_FROM_APP_REVIEW, :app_review_software_hardware, :software_hardware, :has_app_review)
    apply_feedback_tag(TAG_FROM_APP_REVIEW, :app_review_talker_doer, :talker_doer, :has_app_review)
    apply_feedback_tag(TAG_FROM_APP_REVIEW, :app_review_ceo_cto, :ceo_cto, :has_app_review)
    
    apply_feedback_tag(TAG_FROM_PHONE_SCREEN, :phone_screen_rating, :rating, :has_phone_screen)

    apply_feedback_tag(TAG_FROM_DEBRIEF, :debrief_rating, :rating, :has_debrief)
    apply_feedback_tag(TAG_FROM_DEBRIEF, :debrief_edge, :edge, :has_debrief)
    apply_feedback_tag(TAG_FROM_DEBRIEF, :debrief_software_hardware, :software_hardware, :has_debrief)
    apply_feedback_tag(TAG_FROM_DEBRIEF, :debrief_talker_doer, :talker_doer, :has_debrief)
    apply_feedback_tag(TAG_FROM_DEBRIEF, :debrief_healthcare, :healthcare, :has_debrief)
    apply_feedback_tag(TAG_FROM_DEBRIEF, :debrief_visa_exposure, :visa_exposure, :has_debrief)
      
    apply_feedback_tag(TAG_FROM_ABILITY_INTERVIEW, :ability_rating, :rating, :has_ability)
    apply_feedback_tag(TAG_FROM_F2F, :f2f_ceo_cto, :ceo_cto, :has_ability)
    apply_feedback_tag(TAG_FROM_BEHAVIOUR_INTERVIEW, :behaviour_rating, :rating, :has_behaviour)
  end
  
  def apply_feedback_tag(prefix, value_key, tag_set_key, required_key=nil)
    value = @feedback_summary[value_key.to_s]    
    value = parse_feedback_value(value, tag_set_key) || value unless value.nil?
    
    tag_set = tags(tag_set_key)
    tag = {tag: (tag_set.values.select{|v| v.downcase == value}.first)}

    required = @feedback_summary[required_key.to_s] == 'true'
    tag = {remove: true} if ((value || '') == '') && !required # || tag[:tag].nil?
    apply_single_tag(prefix, tag, tag_set)
  end
  
  def parse_feedback_value(value, type)
    case type
    
    when :edge
      case value
      when 'tech edge'
        'technical'
      when 'tech'
        'technical'
      when 'domain edge'
        'domain'
      end    

    when :talker_doer
      case value
      when 'both'
        'talker/doer'
      when 'neither'
        'td-neither'
      when 'unsure'
        'td-unsure'
      end

    when :healthcare
      case value
      when 'yes'
        'healthcare'
      when 'no'
        'not healthcare'
      end

    when :visa_exposure
      case value
      when 'yes'
        'visa exposure'
      when 'no'
        'no visa exposure'
      end
    
    end
  end

  def overall_source(opp)
    potential_source_tags = tags(:source)    
    _tags = opp["tags"].map { |t| t.downcase.strip }
    
    # 0) If manually tagged "rollover", go with that above everything else
    _tags.each { |tag|
      return potential_source_tags[:rollover] if tag.include?('rollover')
    }

    # 1) any merged-in source from a prior opportunity
    opp['tags'].each { |tag|
      return tag.delete_prefix(TAG_ORIGINAL_OVERALL_PREFIX) if tag.start_with?(TAG_ORIGINAL_OVERALL_PREFIX) && (tag != TAG_ORIGINAL_OVERALL_PREFIX + tags(:source, :error))
    }

    # 2) next, look at the source tags for this opportunity
    
    source_tags_map = {
      # source tag => overall source to apply
      /rollover/ => :rollover,
      /sourced/ => :sourced,
      'referral' => :referral,
      'offline' => :offline,
      'organic' => :organic,
      /linkedin [a-z]+/ => :digital_marketing,
      'fb' => :digital_marketing,
      'facebook' => :digital_marketing,
      'twitter' => :digital_marketing,
      'quora' => :digital_marketing,
      'dm' => :digital_marketing,
      'digital marketing' => :digital_marketing,
      'angellist' => :digital_marketing,
      'ai-jobs' => :digital_marketing,
      'researchgate' => :digital_marketing,
      'linkedin' => :sourced
    }
    sources = opp["sources"].map { |s| s.downcase.strip }
    source_tags_map.each { |key, value|
      if key.respond_to?(:match)
        sources.each { |s|
          return potential_source_tags[value] if key.match?(s)
        }
      else
        return potential_source_tags[value] if sources.include?(key)
      end
    }

    # 3) if unclear from source tags, look for clues in generic tags
    
    tags_map = {
      'dm' => :digital_marketing,
      'sourced' => :sourced
    }
    tags_map.each { |key, value|
      if key.respond_to?(:match)
        _tags.each { |s|
          return potential_source_tags[value] if key.match?(s)
        }
      else
        return potential_source_tags[value] if _tags.include?(key)
      end
    }
    
    # 4) if no source tag detected, look at the self-reported source from the application
    
    from_app = Util.find_tag_value(opp, tags(:source), TAG_FROM_APPLICATION)
    return from_app if from_app
    
    # 5) .. otherwise ¯\_(ツ)_/¯ 
    nil
  end

  def source_from_app(opp)
    responses = opp['_app_responses']
    return {msg: "Couldn't find custom question responses."} if responses.nil?

    tags = tags(:source)

    # 1: "who referred you"
    responses.each {|qu|
      if qu[:_text].include?('who referred you')
        return {tag: tags[:referral], field: qu['text'], value: "<not empty>"} if qu['value'] > ''
      end
    }

    responses.each {|qu|
      if qu[:_text].include?('who told you about ef')
        map = [
          ['been on the ef programme', tags[:referral]],
          ['worked at ef', tags[:referral]],
          ['professional network', tags[:organic]],
          ['friends or family', tags[:organic]]
        ]
        source = nil
        map.each { |m|
          return {tag: m[1], field: qu['text'], value: qu['value']} if qu[:_value].include? m[0]
        }
      end
    }

    responses.each {|qu|
      if qu[:_text].include?('how did you hear about ef')
        map = [
          ['directly contacted by ef', tags[:sourced]],
          ['cohort member', tags[:referral]],
          ['someone else', tags[:organic]], # if not already covered above by latter questions
          ['came across ef', tags[:organic]],
          ['event', tags[:offline]]
        ]
        source = nil
        map.each { |m|
          return {tag: m[1], field: qu['text'], value: qu['value']} if qu[:_value].include? m[0]
        }
      end
    }
    
    # otherwise, unable to determine source from application
    nil
  end

  def gender_from_app(opp)
    responses = opp['_app_responses']
    return {msg: "Couldn't find custom question responses."} if responses.nil?

    tags = tags(:gender)
    
    responses.each {|qu|
      if qu[:_text] == 'gender'
        tags.each { |t|
          return {tag: t[1], field: qu['text'], value: qu['value']} if qu[:_value] == t[1].downcase.sub('gender: ', '')
        }
      end
    }
    nil
  end
end
