# frozen_string_literal: true

require 'aws-sdk-core'

# Support both AWS_ENDPOINT and AWS_ENDPOINT_URL for backwards compatibility
endpoint_url = ENV['AWS_ENDPOINT_URL'] || ENV['AWS_ENDPOINT']

if ENV['AWS_ACCESS_KEY_ID'] &&
   ENV['AWS_SECRET_ACCESS_KEY'] &&
   ENV['AWS_REGION'] &&
   endpoint_url
  Aws.config.update(
    {
      region: ENV['AWS_REGION'],
      endpoint: endpoint_url,
      credentials: Aws::Credentials.new(ENV['AWS_ACCESS_KEY_ID'], ENV['AWS_SECRET_ACCESS_KEY'])
    }
  )
end
