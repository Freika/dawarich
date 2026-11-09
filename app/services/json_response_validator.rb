# frozen_string_literal: true

# Validates and parses JSON responses from photo providers. Subclasses name the
# provider and the locale scope of its messages.
class JsonResponseValidator
  def self.validate_and_parse(response, logger: Rails.logger)
    unless response.success?
      return { success: false, error: I18n.t("#{self::I18N_SCOPE}.request_failed_code", code: response.code) }
    end

    content_type = response.headers['content-type'] || response.headers['Content-Type']
    unless content_type.to_s.include?('application/json')
      logger.error("#{self::PROVIDER} returned non-JSON response: #{response.code} #{truncate_body(response.body)}")
      return { success: false,
               error: I18n.t("#{self::I18N_SCOPE}.expected_json_got_content_type",
                             content_type: content_type || 'unknown') }
    end

    { success: true, data: JSON.parse(response.body) }
  rescue JSON::ParserError => e
    logger.error("#{self::PROVIDER} JSON parse error: #{e.message}")
    logger.error("Response body: #{truncate_body(response.body)}")
    { success: false, error: I18n.t("#{self::I18N_SCOPE}.invalid_json_response") }
  end

  private_class_method def self.truncate_body(body, max_length: 1000)
    return '' if body.nil?

    body.length > max_length ? "#{body[0...max_length]}... (truncated)" : body
  end
end
