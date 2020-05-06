# frozen_string_literal: true

require 'csv'
require 'aws-sdk-s3'

class CSV_Writer
  def initialize(filename, data, prefix = '')
    @filename = filename
    @data = data
    @prefix = prefix
  end

  def run
    upload_to_s3(io_object: csv)
  end

  private

  def upload_to_s3(io_object:)
    s3 = Aws::S3::Resource.new(aws_config)
    obj = s3.bucket('lambda-functions-output')
            .object("lever-backup/#{@prefix}/#{@filename}")
    obj.put(body: io_object)

    aws_signed_url(obj)
  end

  def csv
    return @data if @data.class == String
    CSV.generate do |csv|
      @data.each { |row| csv << row }
    end
  end

  def aws_signed_url(obj)
    signer = Aws::S3::Presigner.new(client: Aws::S3::Client.new(aws_config))
    signer.presigned_url(
      :get_object,
      bucket: obj.bucket.name,
      key: obj.key,
      expires_in: 86_400
    )
  end

  def aws_config
    {
      region: ENV['AWS_REGION'],
      access_key_id: ENV['AWS_KEY_ID'],
      secret_access_key: ENV['AWS_SECRET_ACCESS_KEY']
    }
  end
end
