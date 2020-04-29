# frozen_string_literal: true
require_relative '../app/base_rules.rb'

#
# Logic for rules we wish to apply
#

class Rules < BaseRules

  # list of tags for each category, so we can remove when updating with new values
  def all_tags
    {
      source: {
        sourced: 'Sourced',
        referral: 'Referral',
        organic: 'Organic',
        offline: 'Offline',
        offline_organic: 'Offline-or-Organic',
        error: '<error:unknown>'
      }
    }  
  end
  
  def summarise_one_feedback(f)
    result = {}
    
    result
  end

  def summarise_all_feedback(summaries)
    result = {}
    
    result
  end

  def source_from_application(opp)
    return {msg: 'No application'} if !Util.has_application(opp)
    responses = opp['_app_responses']
    return {msg: "Couldn't find custom question responses."} if responses.nil?

    tags = tags(:source)

    # 1: "who referred you"
    responses.each {|qu|
      if qu[:_text].include?('who referred you')
        return {tag: tags[:referral], field: qu['text'], value: "<not empty>"} if qu['value'] > ''
        break
      end
    }

    responses.each {|qu|
      if qu[:_text].include?('who told you about ef')
        map = [
          ['been on the ef programme', tag: tags[:referral]],
          ['worked at ef', tag: tags[:referral]],
          ['professional network', tag: tags[:organicl]],
          ['friends or family', tag: tags[:organic]]
        ]
        source = nil
        map.each { |m|
          source = m[1] if qu[:_value].include? m[0]
        }
        return {tag: source, field: qu['text'], value: qu['value']} unless source.nil?
        break
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
          source = m[1] if qu[:_value].include? m[0]
        }
        return {source: source, field: qu['text'], value: qu['value']} unless source.nil?
        break
      end
    }
    
    # otherwise, unable to determine source from application
    nil
  end

end
