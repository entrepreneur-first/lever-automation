# frozen_string_literal: true

class BaseRules

  def do_update_tags(opp)
    opp(opp)
    update_tags(opp, Util.parse_all_feedback_summary_link(opp))
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
  
  def add_tags(tags)
    @client.add_tags_if_unset(@opp, tags)
  end
  
  def remove_tags(tags)
    @client.remove_tags_if_set(@opp, tags)
  end
  
  def add_links(links)
    @client.add_links(@opp, links)
  end
  
  def add_note(note)
    @client.add_note(@opp, note)
  end
  
  def apply_single_tag(prefix, tag_context, tag_set)
    tag_context = Hash(tag_context)
    if tag_context[:remove]
      tag = update = nil
    else
      tag = tag_context[:tag] || tag_set[:error] || '<error:unknown>'
      update = add_tags(prefix + tag)
    end
    if remove_tags(tag_set.reject {|k,v| v == tag}.values.map{|t| prefix + t})
      update = true
    end
    log.log("Added tag #{prefix}#{tag} because field \"#{tag_context[:field]}\" is \"#{Array(tag_context[:value]).join('; ')}\"") unless update.nil? || tag_context[:remove] || tag_context[:field].nil?
  end

end
