# frozen_string_literal: true

module Photoprism
  class ResponseValidator
    def self.validate_and_parse(response, logger: Rails.logger)
      unless response.success?
        return { success: false,
error: I18n.t('services.photoprism.response_validator.request_failed_code',
              code: response.code) }
      end

      unless json_content_type?(response)
        content_type = response.headers['content-type'] || response.headers['Content-Type'] || 'unknown'
        logger.error("Photoprism returned non-JSON response: #{response.code} #{truncate_body(response.body)}")
        return { success: false,
error: I18n.t('services.photoprism.response_validator.expected_json_got_content_type', content_type: content_type) }
      end

      parsed = JSON.parse(response.body)
      { success: true, data: parsed }
    rescue JSON::ParserError => e
      logger.error("Photoprism JSON parse error: #{e.message}")
      logger.error("Response body: #{truncate_body(response.body)}")
      { success: false, error: I18n.t('services.photoprism.response_validator.invalid_json_response') }
    end

    private_class_method def self.json_content_type?(response)
      content_type = response.headers['content-type'] || response.headers['Content-Type'] || ''
      content_type.include?('application/json')
    end

    private_class_method def self.truncate_body(body, max_length: 1000)
      return '' if body.nil?

      body.length > max_length ? "#{body[0...max_length]}... (truncated)" : body
    end
  end
end
