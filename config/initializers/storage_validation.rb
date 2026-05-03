# frozen_string_literal: true

module Dawarich
  module StorageValidation
    class MissingEnvError < StandardError; end

    REQUIRED_S3_VARS = %w[
      AWS_ACCESS_KEY_ID
      AWS_SECRET_ACCESS_KEY
      AWS_REGION
      AWS_BUCKET
    ].freeze

    module_function

    def validate!
      backend = ENV['STORAGE_BACKEND']
      return unless backend.to_s.downcase == 's3'

      missing = REQUIRED_S3_VARS.reject { |var| ENV[var].to_s.strip.length.positive? }
      return if missing.empty?

      raise MissingEnvError,
            'STORAGE_BACKEND=s3 but the following required environment ' \
            "variable(s) are missing or blank: #{missing.join(', ')}. " \
            'Set them or change STORAGE_BACKEND to a non-S3 value.'
    end
  end
end

Dawarich::StorageValidation.validate! unless Rails.env.test?
