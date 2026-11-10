# frozen_string_literal: true

module Immich
  class ResponseValidator < JsonResponseValidator
    PROVIDER = 'Immich'
    I18N_SCOPE = 'services.immich.response_validator'

    def self.validate_and_parse_body(body_string, logger: Rails.logger)
      return { success: false, error: I18n.t("#{I18N_SCOPE}.invalid_json") } if body_string.nil?

      { success: true, data: JSON.parse(body_string) }
    rescue JSON::ParserError, TypeError => e
      logger.error("JSON parse error: #{e.message}")
      logger.error("Body: #{truncate_body(body_string)}")
      { success: false, error: I18n.t("#{I18N_SCOPE}.invalid_json") }
    end
  end
end
