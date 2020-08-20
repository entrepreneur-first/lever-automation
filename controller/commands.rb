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

      # puts location[:tag] if opp['applications'].length == 0 && !location.nil?
      tagable['unassigned_tagable_to_' + location[:tag]] += 1 if opp['applications'].length == 0 && !location.nil?
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

  def process_opportunities(archived=false, test_mode=false)
    reset
    
    summary = Hash.new(0)
    contacts = Hash.new(0)
    if test_mode
      added_tags = Hash.new(0)
      removed_tags = Hash.new(0)
    end
    
    log_opp_type = archived ? 'archived ' : (archived.nil? ? '' : 'active ')

    log.log("#{test_mode ? '[Test mode - no changes applied] ' : ''}Processing all #{log_opp_type}opportunities..")
    log_index = 0

    client.process_paged_result(OPPORTUNITIES_URL, {archived: archived, expand: client.OPP_EXPAND_VALUES}, "#{log_opp_type}opportunities") { |opp|
    
      contacts[opp['contact']] += 1
      summary[:opportunities] += 1
      summary[:unique_contacts] += 1 if contacts[opp['contact']] == 1
      summary[:contacts_with_duplicates] += 1 if contacts[opp['contact']] == 2
      summary[:contacts_with_3_plus] += 1 if contacts[opp['contact']] == 3

      unless @opps_processed.has_key?(opp['id']) # if not already processed
        results = process_opportunity(opp, test_mode)
        
        results.each { |opp_id, result|        
          summary[:updated] += 1 if result['updated']
          summary[:sent_webhook] += 1 if result['sent_webhook']
          summary[:assigned_to_job] += 1 if result['assigned_to_job']
          summary[:anonymized] += 1 if result['anonymized']
          
          if test_mode
            Array(result['_addTags']).each { |tag|
              added_tags[tag] += 1
            }
            Array(result['_removeTags']).each { |tag|
              removed_tags[tag] += 1
            }
          end
        }
      end
      
      if !test_mode && summary[:updated] > 0 && summary[:updated] % 50 == 0 && summary[:updated] > log_index
        log_index = summary[:updated]
        log.log("Processed #{summary[:opportunities]} #{log_opp_type}opportunities (#{summary[:unique_contacts]} contacts); #{summary[:updated]} changed (#{summary[:sent_webhook]} webhooks sent, #{summary[:assigned_to_job]} assigned to job); #{summary[:contacts_with_duplicates]} contacts with multiple opportunities (#{summary[:contacts_with_3_plus]} with 3+)")
      elsif test_mode && summary[:opportunities] % 50 == 0
        log.log("Processed #{summary[:opportunities]} #{log_opp_type}opportunities (#{summary[:unique_contacts]} contacts); #{summary[:updated]} to be changed (#{summary[:assigned_to_job]} to be assigned to job); #{summary[:contacts_with_duplicates]} contacts with multiple opportunities (#{summary[:contacts_with_3_plus]} with 3+)")
        log.log("added tags: " + JSON.pretty_generate(added_tags)) if added_tags.any?
        log.log("removed tags: " + JSON.pretty_generate(removed_tags)) if removed_tags.any?
      end

      # exit normally in case of termination      
      break if terminating?
    }

    if !test_mode
      log.log("Finished: #{summary[:opportunities]} opportunities (#{summary[:unique_contacts]} contacts); #{summary[:updated]} changed (#{summary[:sent_webhook]} webhooks sent, #{summary[:assigned_to_job]} assigned to job); #{summary[:contacts_with_duplicates]} contacts with multiple opportunities (#{summary[:contacts_with_3_plus]} with 3+)")
    else
      log.log("Finished: #{summary[:opportunities]} #{log_opp_type}opportunities (#{summary[:unique_contacts]} contacts); #{summary[:updated]} to be changed (#{summary[:assigned_to_job]} to be assigned to job); #{summary[:contacts_with_duplicates]} contacts with multiple opportunities (#{summary[:contacts_with_3_plus]} with 3+)")
        log.log("added tags: " + JSON.pretty_generate(added_tags)) if added_tags.any?
        log.log("removed tags: " + JSON.pretty_generate(removed_tags)) if removed_tags.any?
    end
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
  
  def test_rules(opp = nil)
    opp = opp.first if opp.is_a?(Array)
    unless (opp || '') == ''
      client.batch_updates
      prepare_app_responses(opp)
      summarise_feedbacks(opp)
      rules.do_update_tags(opp)
      
      puts JSON.pretty_generate(Util.opp_view_data(opp))
      
      client.batch_updates(false)
    else
      process_opportunities(nil, true)
    end
  end

end
