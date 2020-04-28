# frozen_string_literal: true

class BaseRules

  def update_tags(opp)
    opp(opp)
    tag_source_from_application(opp)
  end
  
  # automatically add tag for the opportunity source based on self-reported data in the application
  def tag_source_from_application(opp)
    return if !Util.has_application(opp) || !Util.is_cohort_app(opp)

    source = source_from_application(opp) || {}
    tag = source[:source] || tags(:source, :error)
    
    add(TAG_SOURCE_FROM_APPLICATION + tag)
    remove(tags(:source).reject {|k,v| k == tag}.values.map{|t| TAG_SOURCE_FROM_APPLICATION + t})
    
    log.log("Added tag #{TAG_SOURCE_FROM_APPLICATION}#{tag} because field \"#{source[:field]}\" is \"#{Array(source[:value]).join('; ')}\"")
  end

  private

  def initialize(client)
    @client = client
  end
  
  def client
    @client
  end
  
  def log
    @client.log
  end
  
  def opp(opp=nil)
    @opp = opp unless opp.nil?
    @opp
  end

  def tags(category=nil, name=nil)
    if category.nil?
      all_tags
    elsif name.nil?
      all_tags[category]
    else
      all_tags[category][name]
    end
  end
  
  def add(tags)
    @client.add_tags_if_unset(@opp, tags)
  end
  
  def remove(tags)
    @client.remove_tags_if_set(@opp, tags)
  end
  
  def add_note(note)
    @client.add_note(@opp, note)
  end
  
end
