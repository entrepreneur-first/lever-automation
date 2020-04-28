# frozen_string_literal: true

#
# Logic for rules we wish to apply
#

class Rules
  
  def self.source_from_application(opp, responses)
    return {msg: 'No application'} if !Util.has_application(opp)
    return {msg: "Couldn't find custom question responses."} if responses.nil?

    # 1: "who referred you"
    responses.each {|qu|
      if qu[:_text].include?('who referred you')
        return {source: "Referral", field: qu['text'], value: "<not empty>"} if qu['value'] > ''
        break
      end
    }

    responses.each {|qu|
      if qu[:_text].include?('who told you about ef')
        map = [
          ['been on the ef programme', 'Referral'],
          ['worked at ef', 'Referral'],
          ['professional network', 'Organic'],
          ['friends or family', 'Organic']
        ]
        source = nil
        map.each { |m|
          source = m[1] if qu[:_value].include? m[0]
        }
        return {source: source, field: qu['text'], value: qu['value']} unless source.nil?
        break
      end
    }

    responses.each {|qu|
      if qu[:_text].include?('how did you hear about ef')
        map = [
          ['directly contacted by ef', 'Sourced'],
          ['cohort member', 'Referral'],
          ['someone else', 'Organic'], # if not already covered above by latter questions
          ['came across ef', 'Offline-or-Organic'],
          ['event', 'Offline']
        ]
        source = nil
        map.each { |m|
          source = m[1] if qu[:_value].include? m[0]
        }
        return {source: source, field: qu['text'], value: qu['value']} unless source.nil?
        break
      end
    }
    
    # otherwise, unable to determine source from application
    nil
  end

  def self.summarise_one_feedback(f)
    result = {}
    
    result
  end

  def self.summarise_all_feedback(summaries)
    result = {}
    
    result
  end

  def self.update_tags(opp, add, remove, add_note)
    tag_source_from_application(opp, add, remove, add_note)
  end
  
  # automatically add tag for the opportunity source based on self-reported data in the application
  def tag_source_from_application(opp, add, remove, add_note)
    remove(TAG_SOURCE_FROM_APPLICATION_ERROR) if opp['tags'].include? TAG_SOURCE_FROM_APPLICATION_ERROR
    
    # we need an application of type posting, to the cohort (not team job)
    return if !Util.has_application(opp) || !Util.is_cohort_app(opp)
    
    # skip if already applied
    opp['tags'].each {|tag|
      return if tag.start_with?(TAG_SOURCE_FROM_APPLICATION) && tag != TAG_SOURCE_FROM_APPLICATION_ERROR
    }
    
    source = Rules.source_from_application(opp, opp['_app_responses'])
    unless source.nil? || source[:source].nil?
      add(TAG_SOURCE_FROM_APPLICATION + source[:source])
      remove(TAG_SOURCE_FROM_APPLICATION_ERROR) if opp['tags'].include? TAG_SOURCE_FROM_APPLICATION_ERROR
      add_note('Added tag ' + TAG_SOURCE_FROM_APPLICATION + source[:source] + "\nbecause field \"" + source[:field] + "\"\nis \"" + (source[:value].class == Array ?
        source[:value].join('; ') :
        source[:value]) + '"')
    else
      add(TAG_SOURCE_FROM_APPLICATION_ERROR) if !opp['tags'].include? TAG_SOURCE_FROM_APPLICATION_ERROR
    end
    true
  end
  
end