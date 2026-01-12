# frozen_string_literal: true

module Immich
  class ResponseValidator
    def self.validate_and_parse(response, logger: Rails.logger)
      return { success: false, error: "Request failed: #{response.code}" } unless response.success?

      unless json_content_type?(response)
        content_type = response.headers['content-type'] || response.headers['Content-Type'] || 'unknown'
        logger.error("Immich returned non-JSON response: #{response.code} #{truncate_body(response.body)}")
        return { success: false, error: "Expected JSON, got #{content_type}" }
      end

      parsed = JSON.parse(response.body)
      { success: true, data: parsed }
    rescue JSON::ParserError => e
      logger.error("Immich JSON parse error: #{e.message}")
      logger.error("Response body: #{truncate_body(response.body)}")
      { success: false, error: "Invalid JSON response" }
    end

    def self.validate_and_parse_body(body_string, logger: Rails.logger)
      return { success: false, error: "Invalid JSON" } if body_string.nil?

      parsed = JSON.parse(body_string)
      { success: true, data: parsed }
    rescue JSON::ParserError, TypeError => e
      logger.error("JSON parse error: #{e.message}")
      logger.error("Body: #{truncate_body(body_string)}")
      { success: false, error: "Invalid JSON" }
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
