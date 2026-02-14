# frozen_string_literal: true

module GooglePhotos
  class ResponseValidator
    def self.validate_and_parse(response, logger: Rails.logger)
      return { success: false, error: "Request failed: #{response.code}" } unless response.success?

      unless json_content_type?(response)
        content_type = response.headers['content-type'] || 'unknown'
        logger.error("Google Photos returned non-JSON response: #{response.code} #{truncate_body(response.body)}")
        return { success: false, error: "Expected JSON, got #{content_type}" }
      end

      parsed = JSON.parse(response.body)
      { success: true, data: parsed }
    rescue JSON::ParserError => e
      logger.error("Google Photos JSON parse error: #{e.message}")
      logger.error("Response body: #{truncate_body(response.body)}")
      { success: false, error: 'Invalid JSON response' }
    end

    private_class_method def self.json_content_type?(response)
      content_type = response.headers['content-type'] || ''
      content_type.include?('application/json')
    end

    private_class_method def self.truncate_body(body, max_length: 1000)
      return '' if body.nil?

      body.length > max_length ? "#{body[0...max_length]}... (truncated)" : body
    end
  end
end
