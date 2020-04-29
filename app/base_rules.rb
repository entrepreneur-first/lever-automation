# frozen_string_literal: true

class BaseRules

  def do_update_tags(opp)
    opp(opp)
    update_tags
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
  
  def apply_single_tag(prefix, tag_context, tag_set)
    tag_context = Hash(tag_context)
    tag = tag_context[:tag] || tag_set[:error])
    update = add(prefix + tag)
    if remove(tag_set.reject {|k,v| v == tag}.values.map{|t| prefix + t})
      update = true
    end
    log.log("Added tag #{prefix}#{tag} because field \"#{tag_context[:field]}\" is \"#{Array(tag_context[:value]).join('; ')}\"") unless update.nil?
  end

end
