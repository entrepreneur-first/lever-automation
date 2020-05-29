# frozen_string_literal: true

module Controller_Import
  
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
      existing_skipped: 0,
      new: 0
    }
    
    rows.each { |row|
      counts[:rows] += 1
      
      opp_params = {
        'id': (Util.get_hash_value_fuzzy(row, 'id') || '').downcase,
        'email': (Util.get_hash_value_fuzzy(row, 'email') || '').downcase,
        'linkedin': (Util.get_hash_value_fuzzy(row, 'linkedin') || '').downcase.sub(/\?.+/, ''),
        'posting': Util.get_hash_value_fuzzy(row, 'posting'),
        'name': Util.get_hash_value_fuzzy(row, 'name'),
        'origin': Util.get_hash_value_fuzzy(row, 'origin'),
        'sources': (Util.get_hash_value_fuzzy(row, 'sources') || '').split(',').map(&:strip),
        'tags': (Util.get_hash_value_fuzzy(row, 'tags') || '').split(',').map(&:strip),
        'phones': (Util.get_hash_value_fuzzy(row, 'phone') || '').split(',').map(&:strip),
        'location': Util.get_hash_value_fuzzy(row, 'location'),
        'headline': Util.get_hash_value_fuzzy(row, 'headline'),
        'createdAt': Util.get_hash_value_fuzzy(row, 'createdat'),
        'stage': Util.get_hash_value_fuzzy(row, 'stageid')
      }
      
      log.log("Looking for existing opportunity via parameters:\n" + opp_params.select{|k,v| [:id, :email, :linkedin, :posting].include?(k)}.map{|k,v| "- #{k}: #{v}"}.join("\n")) if test
      
      if opp_params[:posting].nil? || opp_params[:posting].empty?
        log.log('No job posting ID ("posting") found - unable to process row')
        counts[:errors] += 1
        next
      end
      
      opp, is_new = find_or_create_opportunity(opp_params, "Import: #{Time.now.strftime('%Y-%m-%d')} #{table.table_id}", test)
      
      if is_new
        counts[:new] += 1
      else
        counts[:existing] += 1

        feedback_summary = Util.parse_all_feedback_summary_link(opp)
        if feedback_summary['has_coffee'] == 'true'
          log.log("#{opp['id']}: has coffee feedback form already - skipping")
          counts[:existing_skipped] += 1
          next
        end
      end

      fields = row.reject {|k,v|
        [
          Util.get_hash_key_fuzzy(row, 'id'),
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
        client.add_note(opp, "Imported coffee feedback; " + msg) if remaining.any?
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
      create_params[:emails] = [params[:email]] if (params[:email] || '').match?(/^[^ ]+@[^ ]+\.[^ ]+$/)
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
    
    unless params[:id].nil? || params[:id].empty?
      opp = client.get_opportunity(params[:id])
    end
    
    if opp.nil? && params[:email].match?(/^[^ ]+@[^ ]+\.[^ ]+$/)
      opp = client.opportunities_for_email(params[:email]).select {|opp|
        ['', params[:posting]].include?(Util.view_flat(opp)['application__posting'] || '')
      }.sort_by {|opp|
        opp['lastInteractionAt']
      }.last
    end
    
    # match linkedin or other urls (sometimes used for personal websites instead of linkedin)
    if opp.nil? && params[:linkedin].match?(/(linkedin\.com\/.+)|((www\.|\/\/)[^\.\s]+\.[^\.\s]+)/)
      ids = bigquery.query("SELECT id FROM #{bigquery.table.query_id}_view WHERE LOWER(links) LIKE '%#{Util.escape_sql(params[:linkedin].sub(/^[a-z]+:\/\/(www\.)/, '').sub(/\/+$/, ''))}%' AND application__posting IN ('#{Util.escape_sql(params[:posting])}', '', null) ORDER BY lastInteractionAt DESC LIMIT 1", '')
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
