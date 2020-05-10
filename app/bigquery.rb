# frozen_string_literal: true
require "google/cloud/bigquery"

BIGQUERY_IMPORT_TIMESTAMP_COLUMN = 'bigquery_import_timestamp'

class BigQuery
  def initialize(log=nil)
    @log = log
    @bq = Google::Cloud::Bigquery.new(credentials: JSON.parse(ENV['GOOGLE_APPLICATION_CREDENTIALS']))
    @dataset = @bq.dataset(ENV['BIGQUERY_DATASET'])
    @table = @dataset.table(ENV['BIGQUERY_TABLE']) || create_empty_table
  end

  def bq
    @bq
  end
  
  def dataset
    @dataset
  end
  
  def table
    @table
  end
  
  def create_empty_table
    table = @dataset.create_table(ENV['BIGQUERY_TABLE']) do |t|
      t.schema do |schema|
        schema.string BIGQUERY_IMPORT_TIMESTAMP_COLUMN
        schema.string 'id'
        schema.string 'contact'
        schema.string 'createdAt'
        schema.string 'createdAt__datetime'
      end
    end
    @dataset.create_view(ENV['BIGQUERY_TABLE'] + '_view', 
"SELECT 
  * EXCEPT(row_number) 
FROM ( 
  SELECT 
    *, 
    ROW_NUMBER() OVER (
      PARTITION BY `id` ORDER BY `#{BIGQUERY_IMPORT_TIMESTAMP_COLUMN}` DESC
    ) row_number 
  FROM 
    #{table.query_id}
  ) 
WHERE 
  `row_number` = 1 AND `id` IS NOT NULL"
    )
    table
  end

  def query(select, from=nil)
    from ||= " FROM #{@table.query_id}"
    @dataset.query select + from
  end

  def insert(rows)
    rows = format_rows(rows)
    @table.insert(rows, skip_invalid: true)
  end

  def insert_async(rows)
    rows = format_rows(rows)
    inserter.insert rows
  end
  
  def insert_ensuring_columns(rows)
    ensure_columns(extract_headers(rows))
    insert(rows)
  end
  
  def insert_async_ensuring_columns(rows)
    ensure_columns(extract_headers(rows))
    insert_async(rows)
  end

  def wait
    inserter.stop.wait! if @inserter
  end

  def ensure_columns(names)
    columns = @table.headers
    names.map!(&:to_sym).reject!{ |name| columns.include?(name) }
    return if names.empty?
    add_columns(names)
    # sleep to give BigQuery time to register the new columns
    # BQ schema is eventually-consistent: inserts may fail when new columns not yet recognised
    # for several minutes after schema updated
    sleep(120)
  end

  def add_columns(names)
    names = Array(names).sort
    log("BigQuery: adding columns to table #{@table.query_id}: #{names.join(', ')}")
    @table.schema do |schema|
      names.each { |name|
        schema.string name
      }
    end
  end
  
  private

  def log(msg)
    if @log
      @log.log(msg) if @log.verbose?
    else
      puts msg
    end
  end
  
  def error(msg)
    if @log
      @log.error(msg)
    else
      puts msg
    end
  end
  
  def inserter
    @inserter ||= @table.insert_async(skip_invalid: true) do |result|
      if result.error?
        log result.error
      else
        log "BigQuery: inserted #{result.insert_count} rows " \
          "with #{result.error_count} errors"
        result.insert_errors.each { |e|
          error "BigQuery: " + e.errors.to_s
        }
      end
    end
  end
  
  def extract_headers(rows)
    headers = []
    rows = [rows] unless rows.class == Array
    rows.each { |row|
      headers = headers | row.keys.map(&:to_sym)
    }
    headers
  end
  
  def format_rows(rows)
    rows = [rows] unless rows.class == Array
      rows.map! { |row|
        row.transform_values(&:to_s)
      }
    rows
  end
end
