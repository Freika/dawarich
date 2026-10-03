# frozen_string_literal: true

module FamilyGoldenHeaders
  FIXED = { 'x-request-id' => '00000000-0000-0000-0000-000000000000', 'x-runtime' => '0.000000' }.freeze

  def self.fixed(headers) = headers.merge(FIXED.slice(*headers.keys))
end
