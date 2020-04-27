# frozen_string_literal: true

#
# Logic for rules we wish to apply
#

class Rules
  
  def self.source_from_application(opp)
    return {msg: 'No application'} if !Util.has_application(opp)
    
    # responses to questions are subdivided by custom question set - need to combine them together
    responses = opp['applications'][0]['customQuestions'].reduce([]) {|a, b| a+b['fields']} if opp.dig('applications', 0, 'customQuestions')
    return {msg: "Couldn't find custom question responses."} if responses.nil?

    # simply question titles to lowercase a-z only to minimise mismatch due to inconsistent naming
    responses.map! { |qu|
      qu.merge!({
        _text: qu['text'].downcase.gsub(/[^a-z ]/, ''),
        _value: (qu['value'].class == Array ? qu['value'].join(' ') : qu['value']).downcase.gsub(/[^a-z ]/, ''),
      })
    }

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

end