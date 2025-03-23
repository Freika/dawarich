# frozen_string_literal: true

require 'aws-sdk-core'

Aws.config.update(
  {
    region: ENV['AWS_REGION'],
    endpoint: ENV['AWS_ENDPOINT'],
    credentials: Aws::Credentials.new(ENV['AWS_ACCESS_KEY_ID'], ENV['AWS_SECRET_ACCESS_KEY'])
  }
)
