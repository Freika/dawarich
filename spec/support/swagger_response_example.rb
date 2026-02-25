# frozen_string_literal: true

module SwaggerResponseExample
  def self.capture(example, response)
    return if response.nil? || response.body.blank?

    content = example.metadata[:response][:content] || {}
    example.metadata[:response][:content] = content.merge(
      'application/json' => {
        example: JSON.parse(response.body, symbolize_names: true)
      }
    )
  end
end
