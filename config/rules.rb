# frozen_string_literal: true
require_relative '../app/base_rules.rb'

#
# Logic for rules we wish to apply
#

TAG_FROM_APPLICATION = AUTO_TAG_PREFIX + 'App: '
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
        offline_organic: 'Offline-or-Organic'
      },
      gender: {
        female: 'Female',
        male: 'Male',
        other: 'Other',
        prefer_not_say: 'Gender: Prefer not to say'
      },
      rating: {
        _4: '4 - Strong Hire',
        _3: '3 - Hire',
        _2: '2 - No Hire',
        _1: '1 - Strong No Hire'
      },
      edge: {
        technical: 'Technical',
        domain: 'Domain',
        cat_talker: 'Catalyst Talker',
        cat_doer: 'Catalyst Doer',
        no_edge: 'No edge'
      },
      eligibility: {
        eligible: 'Eligible',
        ineligible: 'Ineligible'
      },
      software_hardware: {
        software: 'Software',
        hardware: 'Hardware'
      },
      talker_doer: {
        talker: 'Talker',
        doer: 'Doer',
        both: 'Talker/Doer',
        neither: 'TD-Neither',
        unsure: 'TD-Unsure'
      },
      ceo_cto: {
        ceo: 'CEO',
        cto: 'CTO'
      },
      visa_exposure: {
        yes: 'Visa Exposure=Y',
        no: 'Visa Exposure=N'
      },
      healthcare: {
        yes: 'Healthcare=Y',
        no: 'Healthcare=N'
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
  
  def summarise_one_feedback(f)
    result = {}

    # feedback type
    type = Util.simplify_str(f['text'])
    result['title'] = type
    result['type'] =
      if type.include?('coffee')
        'coffee'
      elsif type.include?('phone screen')
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
    result['rating'] = (f['fields'].select{|f| f[:_text] == 'rating' || f[:_text].include?('could pass ic')}.first || {})[:_value]
    
    if result['type'] == 'coffee'
      # gender
      result['gender'] = (f['fields'].select{|f| f[:_text] == 'gender'}.first || {})[:_value]
      
      # eligibile
      # TODO: question title/format varies
      result['eligibile'] = (f['fields'].select{|f| f[:_text].include?('eligible for the upcoming cohort')}.first || {})[:_value]
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
      # software/hardware
      # TODO: question?
      result['software_hardware'] = (f['fields'].select{|f| f[:_text].include?('software')}.first || {})[:_value]
     
      # talker/doer
      # TODO: question?
      result['talker_doer'] = (f['fields'].select{|f| f[:_text].include?('talker')}.first || {})[:_value]

      # industry
      # TODO: question?
      result['industry'] = (f['fields'].select{|f| f[:_text] == 'industry'}.first || {})[:_value]

      # industry
      # TODO: question?
      result['technology'] = (f['fields'].select{|f| f[:_text] == 'technology'}.first || {})[:_value]
    end    
    
    if ['coffee', 'app_review', 'debrief'].include?(result['type'])
      # edge
      # TODO: question title varies
      result['edge'] = (f['fields'].select{|f| f[:_text].include?('edge')}.first || {})[:_value]
    end
    
    if result['type'] == 'debrief'
      # healthcare
      # TODO: question?
      result['healthcare'] = (f['fields'].select{|f| f[:_text] == 'healthcare'}.first || {})[:_value]

      # visa exposure
      # TODO: question?
      result['visa_exposure'] = (f['fields'].select{|f| f[:_text] == 'visa exposure'}.first || {})[:_value]
    end
        
    # when scorecard was completed
    result['submitted_at'] = f['completedAt']
    # scorecard submitted by
    result['submitted_by'] = f['user']
    
    result
  end

  def summarise_all_feedback(summaries)
    return {} unless summaries.any?
  
    result = {
      has_coffee: false,
      coffee_rating: nil,
      coffee_edge: nil,
      coffee_gender: nil,
      coffee_eligible: nil,
      coffee_completed_at: nil,
      coffee_completed_by: nil,
      
      has_phone_screen: false,
      phone_screen_rating: nil,
      phone_screen_completed_at: nil,
      phone_screen_completed_by: nil,
      
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
      debrief_visa_exposure: nil
    }
    
    summaries.each {|f|
      case f['type']
      when 'coffee'
        result[:has_coffee] = true
        result[:coffee_rating] = f['rating']
        result[:coffee_edge] = f['edge']
        result[:coffee_gender] = f['gender']
        result[:coffee_eligible] = f['eligible']
        result[:coffee_completed_at] = f['submitted_at']
        result[:coffee_completed_by] = f['submitted_by']
        
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
      end
    }
  
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
    
    # feedback
    apply_feedback_tag(TAG_FROM_COFFEE, :coffee_rating, :rating)
    apply_feedback_tag(TAG_FROM_COFFEE, :coffee_edge, :edge)
    apply_feedback_tag(TAG_FROM_COFFEE, :coffee_gender, :gender)
    apply_feedback_tag(TAG_FROM_COFFEE, :coffee_eligible, :eligibility)

    apply_feedback_tag(TAG_FROM_APP_REVIEW, :app_review_rating, :rating)
    apply_feedback_tag(TAG_FROM_APP_REVIEW, :app_review_edge, :edge)
    apply_feedback_tag(TAG_FROM_APP_REVIEW, :app_review_software_hardware, :software_hardware)
    apply_feedback_tag(TAG_FROM_APP_REVIEW, :app_review_talker_doer, :talker_doer)
    apply_feedback_tag(TAG_FROM_APP_REVIEW, :app_review_ceo_cto, :ceo_cto)
    
    apply_feedback_tag(TAG_FROM_PHONE_SCREEN, :phone_screen_rating, :rating)

    apply_feedback_tag(TAG_FROM_DEBRIEF, :debrief_rating, :rating)
    apply_feedback_tag(TAG_FROM_DEBRIEF, :debrief_edge, :edge)
    apply_feedback_tag(TAG_FROM_DEBRIEF, :debrief_software_hardware, :software_hardware)
    apply_feedback_tag(TAG_FROM_DEBRIEF, :debrief_talker_doer, :talker_doer)
    apply_feedback_tag(TAG_FROM_DEBREIF, :debrief_healthcare, :healthcare)
    apply_feedback_tag(TAG_FROM_DEBREIF, :debrief_visa_exposure, :visa_exposure)
      
    apply_feedback_tag(TAG_FROM_ABILITY_INTERVIEW, :ability_rating, :rating)
    apply_feedback_tag(TAG_FROM_F2F, :f2f_ceo_cto, :ceo_cto))
    apply_feedback_tag(TAG_FROM_BEHAVIOUR_INTERVIEW, :behaviour_rating, :rating)
      
  end
  
  def apply_feedback_tag(prefix, value_key, tag_set_key)
    value = @feedback_summary[value_key]
    value = parse_feedback_value(value, tag_set_key) || value unless value.nil?
    
    tag_set = tags(tag_set_key)
    tag = {:tag: tag_set.values.select{|v| v.downcase == value}.first}
    tag = {:remove: true} if value.nil? # || tag[:tag].nil?
    
    apply_single_tag(prefix, tag, tag_set}
  end
  
  def parse_feedback_value(value, type)
    case type
    
    when :edge
      case value
      when 'tech edge'
        'technical'
      when 'domain edge'
        'domain'
      else value
      end    

    when :talker_doer
      case value
      when 'both'
        'talker/doer'
      when 'neither'
        'td-neither'
      when 'unsure'
        'td-unsure'
      else value
      end

    when :healthcare
      case value
      when 'Yes'
        'healthcare=y'
      when 'No'
        'healthcare=n'
      end      

    when :visa_exposure
      case value
      when 'Yes'
        'visa exposure=y'
      when 'No'
        'visa exposure=n'
      end       
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
          ['professional network', tags[:organicl]],
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
          ['came across ef', tags[:offline_organic]],
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
