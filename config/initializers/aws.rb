# frozen_string_literal: true

require 'aws-sdk-core'

if ENV['AWS_ACCESS_KEY_ID'] &&
   ENV['AWS_SECRET_ACCESS_KEY'] &&
   ENV['AWS_REGION'] &&
   ENV['AWS_ENDPOINT']
  Aws.config.update(
    {
      region: ENV['AWS_REGION'],
      endpoint: ENV['AWS_ENDPOINT'],
      credentials: Aws::Credentials.new(ENV['AWS_ACCESS_KEY_ID'], ENV['AWS_SECRET_ACCESS_KEY'])
    }
  )
end
