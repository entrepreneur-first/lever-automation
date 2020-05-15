# frozen_string_literal: true

require_relative '../app/export_filter'
require_relative '../app/csv_writer'

module Controller_Commands

  def summarise_opportunities
    summary = Hash.new(0)
    contacts = Hash.new(0)
    tagable = Hash.new(0)
    untagable = Hash.new(0)
    
    client.process_paged_result(OPPORTUNITIES_URL, {archived: false, expand: client.OPP_EXPAND_VALUES}, 'active opportunities') { |opp|
    
      contacts[opp['contact']] += 1
      summary[:opportunities] += 1
      summary[:unique_contacts] += 1 if contacts[opp['contact']] == 1
      summary[:contacts_with_duplicates] += 1 if contacts[opp['contact']] == 2
      summary[:contacts_with_3_plus] += 1 if contacts[opp['contact']] == 3

      location = location_from_tags(opp) if opp['applications'].length == 0
      summary[:unassigned_leads_aka_opportunities_without_posting] += 1 if opp['applications'].length == 0
      summary[:unassigned_leads_with_detected_location] += 1 if opp['applications'].length == 0 && !location.nil?
      summary[:unassigned_leads_without_detected_location] += 1 if opp['applications'].length == 0 && location.nil?

      # puts location[:name] if opp['applications'].length == 0 && !location.nil?
      tagable['unassigned_tagable_to_' + location[:name]] += 1 if opp['applications'].length == 0 && !location.nil?
      tagable['unassigned_tagable_owned_by_' + (opp.dig('owner','name') || '')] += 1 if opp['applications'].length == 0 && !location.nil?
      tagable['unassigned_tagable_sourced_by_' + (opp.dig('sourcedBy','name') || '')] += 1 if opp['applications'].length == 0 && !location.nil?
      
      untagable['untagable_owned_by_' + (opp.dig('owner','name') || '')] += 1 if opp['applications'].length == 0 && location.nil?
      untagable['untagable_sourced_by_' + (opp.dig('sourcedBy','name') || '')] += 1 if opp['applications'].length == 0 && location.nil?
      
      summary[:cohort_applications] += 1 if Util.has_application(opp) && Util.is_cohort_app(opp)
      summary[:team_applications] += 1 if Util.has_application(opp) && !Util.is_cohort_app(opp)

      summary[:leads_assigned_to_cohort_posting] += 1 if opp['applications'].length > 0 && opp['applications'][0]['type'] != 'posting' && Util.is_cohort_app(opp)
      summary[:leads_assigned_to_team_posting] += 1 if opp['applications'].length > 0 && opp['applications'][0]['type'] != 'posting' && !Util.is_cohort_app(opp)
      
      if summary[:opportunities] % 500 == 0
        # log.log(JSON.pretty_generate(contacts))
        puts JSON.pretty_generate(summary)
        puts JSON.pretty_generate(tagable)
        puts JSON.pretty_generate(untagable)
      end
    }
    log.log(JSON.pretty_generate(summary))
    log.log(JSON.pretty_generate(tagable))
    log.log(JSON.pretty_generate(untagable))
  end

  def process_opportunities(archived=false)
    summary = Hash.new(0)
    contacts = Hash.new(0)
    
    log_opp_type = archived ? 'archived ' : (archived.nil? ? '' : 'active ')

    log.log("Processing all #{log_opp_type}opportunities..")
    log_index = 0

    client.process_paged_result(OPPORTUNITIES_URL, {archived: archived, expand: client.OPP_EXPAND_VALUES}, "#{log_opp_type}opportunities") { |opp|
    
      contacts[opp['contact']] += 1
      summary[:opportunities] += 1
      summary[:unique_contacts] += 1 if contacts[opp['contact']] == 1
      summary[:contacts_with_duplicates] += 1 if contacts[opp['contact']] == 2
      summary[:contacts_with_3_plus] += 1 if contacts[opp['contact']] == 3

      result = process_opportunity(opp)
      
      summary[:updated] += 1 if result['updated']
      summary[:sent_webhook] += 1 if result['sent_webhook']
      summary[:assigned_to_job] += 1 if result['assigned_to_job']
      summary[:anonymized] += 1 if result['anonymized']

      if summary[:updated] > 0 && summary[:updated] % 50 == 0 && summary[:updated] > log_index
        log_index = summary[:updated]
        log.log("Processed #{summary[:opportunities]} #{log_opp_type}opportunities (#{summary[:unique_contacts]} contacts); #{summary[:updated]} changed (#{summary[:sent_webhook]} webhooks sent, #{summary[:assigned_to_job]} assigned to job); #{summary[:contacts_with_duplicates]} contacts with multiple opportunities (#{summary[:contacts_with_3_plus]} with 3+)")
      end

      # exit normally in case of termination      
      break if terminating?
    }

    log.log("Finished: #{summary[:opportunities]} opportunities (#{summary[:unique_contacts]} contacts); #{summary[:updated]} changed (#{summary[:sent_webhook]} webhooks sent, #{summary[:assigned_to_job]} assigned to job); #{summary[:contacts_with_duplicates]} contacts with multiple opportunities (#{summary[:contacts_with_3_plus]} with 3+)")
  end

  def export_to_bigquery(archived=nil, all_fields=true, test=false)
    prefix = Time.now
    log_opp_type = archived ? 'archived ' : (archived.nil? ? '' : 'active ')
    log.log("Exporting full data for all #{log_opp_type}opportunities to BigQuery..")
    log_index = 0
    data = []
    data_headers = {}
    
    client.process_paged_result(
      OPPORTUNITIES_URL, {
        archived: archived,
        expand: client.OPP_EXPAND_VALUES
      }, "#{log_opp_type}opportunities"
    ) { |opp|
      # filter to cohort job or no posting
      next if Util.has_posting(opp) && !Util.is_cohort_app(opp)
      log_index += 1
      data << Util.flatten_hash(Util.opp_view_data(opp).merge({"#{BIGQUERY_IMPORT_TIMESTAMP_COLUMN}": Time.now.to_i*1000}))
      if log_index % 100 == 0
        bigquery.insert_async_ensuring_columns(data)
        data = []
      end
      break if test && (log_index == 100)
    }
    
    log.log("Finished full export of #{log_index} #{log_opp_type}opportunities to BigQuery")
  end

  def export_to_csv(archived=nil, all_fields=true, test=false)
    prefix = Time.now
    log_opp_type = archived ? 'archived ' : (archived.nil? ? '' : 'active ')
    log.log("Exporting full data for all #{log_opp_type}opportunities to CSV..")
    log_index = 0
    data = []
    data_headers = {}
    
    client.process_paged_result(
      OPPORTUNITIES_URL, {
        archived: archived,
        expand: client.OPP_EXPAND_VALUES
      }, "#{log_opp_type}opportunities"
    ) { |opp|
      # filter to cohort job or no posting
      next if Util.has_posting(opp) && !Util.is_cohort_app(opp)
      log_index += 1
      data << Util.view_flat(opp).each { |k,v| data_headers[k] = true }
      break if test && (log_index == 100)
    }
    
    headers = CSV_EXPORT_HEADERS
    headers += data_headers.keys.map{|k| k.to_s}.reject{|k| CSV_EXPORT_HEADERS.include?(k)}.sort if all_fields
    
    url = CSV_Writer.new(
      'full_data.csv',
      CSV.generate do |csv|
        csv << headers
        data.each do |row|
          csv << headers.map{|k| row[k]}
        end
      end,
      prefix
    ).run

    log.log("Finished full export of #{log_index} #{log_opp_type}opportunities to CSV on AWS S3: #{url}")
    url
  end

  def export_to_csv_v1(feedback_since=nil)
    prefix = Time.now
    posting_ids = COHORT_JOBS.map{|j| j[:posting_id]}

    opps = client.all_opportunities(posting_ids)
    url1 = CSV_Writer.new('opportunities.csv', ExportFilter.new(opps).opportunities, prefix).run

    # Feedback
    feedbacks = client.feedback(opps.map{|opp| opp.fetch('id') if Util.has_feedback(opp)}.reject{|o| o.nil?})
    url2 = CSV_Writer.new('feedback.csv', ExportFilter.new(feedbacks).feedback, prefix).run

    { opportunities: url1, feedback: url2 }
  end

  def export_via_webhook(archived)
    # dont do this; it overwhelms zapier/gsheets..
    log.log('export via webhooks is disabled')
    return

    log_opp_type = archived ? 'archived ' : (archived.nil? ? '' : 'active ')
    log.log("Sending full webhooks for all #{log_opp_type}opportunities..")
    i = 0

    client.process_paged_result(OPPORTUNITIES_URL, {
      archived: archived,
      expand: client.OPP_EXPAND_VALUES
    }, "#{log_opp_type}opportunities") { |opp|
      i += 1
      FULL_WEBHOOK_URLS.each {|url|
        _webhook(url, opp, Time.now.to_i*1000, true)
      }
      log.log("..exported #{i} opportunities via webhook") if i % 100 == 0
    }  
  end
  
  def test_rules(opp)
    client.batch_updates
    summarise_feedbacks(opp)
    rules.do_update_tags(opp)
    
    puts JSON.pretty_generate(Util.opp_view_data(opp))
    
    client.batch_updates(false)
  end  

  def slack_lookup(slack_params)
    format_slack_response(find_opportunities(slack_params['text']), slack_params)
  end

  def find_opportunities(search, limit=nil)
    limit ||= 4
    
    search_esc = Util.escape_sql(search.strip.downcase)
    
    from = "FROM #{bigquery.table.query_id} WHERE LOWER(name) LIKE '#{search_esc}' OR links LIKE '%#{search_esc}%' OR emails LIKE '%#{search_esc}%'"
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

  def import_from_bigquery(table_name, test=false)
    table = bigquery.dataset.table table_name
    if table.nil? || table.id.nil?
      log.log("BigQuery table not found: #{bigquery.dataset.dataset_id}.#{table_name}")
      return
    end
    
    log.log("<Dry-run import - no changes actually applied>") if test
    
    log.log("Importing from BigQuery table: #{table.query_id}")
    rows = bigquery.query("SELECT * FROM #{table.query_id}", '')
    
    counts = {
      rows: 0,
      errors: 0,
      existing: 0,
      new: 0
    }
    
    rows.each { |row|
      counts[:rows] += 1
      
      opp_params = {
        'email': (Util.get_hash_value_fuzzy(row, 'email') || '').downcase,
        'linkedin': (Util.get_hash_value_fuzzy(row, 'linkedin') || '').downcase.sub(/\?.+/, ''),
        'posting': Util.get_hash_value_fuzzy(row, 'posting'),
        'name': Util.get_hash_value_fuzzy(row, 'name'),
        'origin': Util.get_hash_value_fuzzy(row, 'origin'),
        'sources': (Util.get_hash_value_fuzzy(row, 'sources') || '').split(',').map(&:strip),
        'tags': (Util.get_hash_value_fuzzy(row, 'tags') || '').split(',').map(&:strip),
        'phones': (Util.get_hash_value_fuzzy(row, 'phone') || '').split(',').map(&:strip),
        'location': Util.get_hash_value_fuzzy(row, 'location'),
        'headline': Util.get_hash_value_fuzzy(row, 'headline')
      }
      opp_params[:createdAt] = Util.get_hash_value_fuzzy(row, 'createdat')
      opp_params[:stage] = Util.get_hash_value_fuzzy(row, 'stageid')
      
      log.log("Looking for existing opportunity via parameters:\n" + opp_params.select{|k,v| [:email, :linkedin, :posting].include?(k)}.map{|k,v| "- #{k}: #{v}"}.join("\n")) if test
      
      if opp_params[:posting].empty?
        log.log('No job posting ID ("posting") found - unable to process row')
        counts[:errors] += 1
        next
      end
      
      opp, is_new = find_or_create_opportunity(opp_params, "Import: #{Time.now.strftime('%Y-%m-%d')} #{table.table_id}", test)
      
      if is_new
        counts[:new] += 1
      else
        counts[:existing] += 1
      end

      fields = row.reject {|k,v|
        [
          Util.get_hash_key_fuzzy(row, 'posting'),
          Util.get_hash_key_fuzzy(row, 'name'),
          Util.get_hash_key_fuzzy(row, 'email'),
          Util.get_hash_key_fuzzy(row, 'linkedin')
        ].include?(k)
      }.transform_keys {|k|
        k.to_s.sub(/^coffee_/i, '')
      }
      
      feedback = prepare_coffee_feedback(fields)
      remaining = fields.reject{|k,v| feedback[:keys].include?(k)}
      
      msg = "additional fields:\n" + remaining.map{|k,v| "- #{k}: #{v}"}.sort.join("\n")
      
      unless test
        add_coffee_feedback(opp, feedback[:fields])
        client.add_note(opp, "Imported coffee feedback; " + msg)
      else
        log.log("Ready to add coffee feedback:\n" + feedback[:fields].map{|v| "- #{v['text']}: #{v['value']}"}.sort.join("\n"))
        log.log(msg)
      end
    }
    
    log.log("Finished importing from BigQuery table: #{table.query_id}\n" + JSON.pretty_generate(counts))
  end

  def find_or_create_opportunity(params, tag, test)
    opp = find_opportunity(params)
    if opp
      is_new = false
      client.add_tag(opp, AUTO_TAG_PREFIX + tag + "-existing") unless test
    else
      is_new = true
      create_params = {
        name: params[:name],
        postings: [params[:posting]],
        origin: ([(params[:origin] || 'sourced').downcase] & ['agency', 'applied', 'internal', 'referred', 'sourced', 'university']).first,
        sources: Array(params[:source]),
        tags: [AUTO_TAG_PREFIX + tag + "-new"] + (Array(params[:tags]) || [])
      }
      create_params[:emails] = [params[:email]] if !(params[:email] || '').empty?
      create_params[:links] = [params[:linkedin]] if !(params[:linkedin] || '').empty?
      create_params[:createdAt] = params[:createdAt] if params[:createdAt]
      create_params[:stage] = params[:stage_id] if params[:stage_id]
      create_params[:phones] = Array(params[:phones]) if params[:phones]
      create_params[:location] = params[:location] if params[:location]
      create_params[:headline] = params[:headline] if params[:headline]
      
      unless test
        opp = create_opportunity(create_params)
      else
        log.log("Ready to create opportunity:\n" + JSON.pretty_generate(create_params))
      end
    end
    [opp, is_new]
  end

  def find_opportunity(params)
    opp = nil
    if params[:email].match?(/.+@.+\..+/)
      opp = client.opportunities_for_contact(params[:email]).select {|opp|
        ['', params[:posting]].include?(Util.view_flat(opp)['application__posting'] || '')
      }.sort_by {|opp|
        opp['lastInteractionAt']
      }.last
    end
    
    if opp.nil? && params[:linkedin].match?(/linkedin\.com\/.+/)
      ids = bigquery.query("SELECT id FROM #{bigquery.table.query_id}_view WHERE LOWER(links) LIKE '%#{Util.escape_sql(params[:linkedin])}%' AND application__posting IN ('#{Util.escape_sql(params[:posting])}', '', null) ORDER BY lastInteractionAt DESC LIMIT 1", '')
      opp = client.get_opportunity(ids[0][:id]) if ids[0]
    end
    
    log.log("Existing opportunity: #{opp['id']}") if opp
    opp
  end

  def create_opportunity(params)
    opp = client.create_opportunity(params)['data']
    log.log("Created opportunity: #{opp['id']}") if opp
    opp
  end

  def prepare_coffee_feedback(fields)
    client.prepare_feedback(COFFEE_FEEDBACK_FORM, fields)
  end
  
  def add_coffee_feedback(opp, fields)
    client.add_profile_form(opp, COFFEE_FEEDBACK_FORM, fields)
  end

end
