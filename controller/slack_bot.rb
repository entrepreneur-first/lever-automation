# frozen_string_literal: true

module Controller_SlackBot

  def slack_lookup(slack_params)
    format_slack_response(find_opportunities(slack_params['text']), slack_params)
  end

  def find_opportunities(search, limit=nil)
    limit ||= 4
    
    search_esc = Util.escape_sql(search.strip.downcase)
    
    from = "FROM #{bigquery.table.query_id}_view WHERE LOWER(name) LIKE '#{search_esc}' OR links LIKE '%#{search_esc}%' OR emails LIKE '%#{search_esc}%'"
    counts = bigquery.query("SELECT COUNT(*) total, COUNT(DISTINCT contact) contacts #{from}", '')[0]
    contacts = bigquery.query("SELECT DISTINCT(contact) contact #{from} LIMIT #{limit}", '').map {|c| c[:contact]}
    
    return {count: 0, opportunities: []} if contacts.empty?
    
    {
      count: counts[:total],
      contacts: counts[:contacts],
      has_more: (counts[:contacts] > limit),
      opportunities: client.get_paged_result(OPPORTUNITIES_URL, {contact_id: contacts, expand: client.OPP_EXPAND_VALUES}, 'opportunities_for_contact_ids')
    }
  end

  def format_slack_response(results, slack_params)
    return [{
    		"type": "section",
    		"text": {
    			"type": "mrkdwn",
    			"text": "No Lever search results found for `#{slack_params['text']}`"
    		}
      }] if results[:opportunities].empty?
    
    blocks = [
      {
    		"type": "section",
    		"text": {
    			"type": "mrkdwn",
    			"text": "Lever search results for `#{slack_params['text']}`#{results[:has_more] ? " (displaying #{results[:opportunities].size} of #{results[:count]} opportunities for #{results[:contacts]} contacts)" : ''}:"
    		}
  	  },
  	  {
  		"type": "divider"
  	  }
  	]
	
    results[:opportunities].each{ |opp|
      opp_data = Util.opp_view_data(opp)
      blocks += [
        {
          "type": "section",
          "text": {
            "type": "mrkdwn",
            "text": "#{opp['archived'].nil? ? '👤 ' : '👻 '}<#{opp['urls']['show']}|*#{opp['name']}* - view on Lever>#{opp['archived'].nil? ? '' : ' [archived]'}" \
              "#{opp_data['application__posting__text'] ? "\n" + opp_data['application__posting__text'] : ''}" \
              "\n*Email#{opp['emails'].size > 1 ? 's' : ''}:* #{opp['emails'].join(', ')}" \
              "#{opp['links'].select{|l| l.include?('linkedin.com')}.any? ? "\n*LinkedIn:* #{opp['links'].select{|l| l.include?('linkedin.com')}.join(', ')}" : ''}" \
              "\n*Stage:* #{opp['stage']['text']}" \
              "\n*Last updated:* #{opp_data['lastInteractionAt__datetime']}"
          }
        }
      ]
    }
    
    blocks += [
      { "type": "divider" },
      {
        "type": "context",
        "elements": [
          {
            "type": "mrkdwn",
            "text": "To search, type `/lever <name, email or url>` - or `/leverme` to show only to yourself."
          }
        ]
      }
    ]
    
    blocks
  end
  
end
