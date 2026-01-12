# frozen_string_literal: true

class Immich::ResponseAnalyzer
  attr_reader :response

  def initialize(response)
    @response = response
  end

  def permission_error?
    return false unless response.code.to_i == 403

    result = Immich::ResponseValidator.validate_and_parse_body(response.body)
    return false unless result[:success]

    result[:data]['message']&.include?('asset.view') || false
  end

  def error_message
    return 'Immich API key missing permission: asset.view' if permission_error?

    'Failed to fetch thumbnail'
  end
end
