# frozen_string_literal: true

require 'json'
require 'time'

module ApiJwtFixture
  ROOT = File.expand_path('../../fixtures/auth/api_auth', __dir__)
  INPUTS = JSON.parse(File.read(File.join(ROOT, 'jwt_inputs.json'))).freeze

  def self.secret(role)
    [INPUTS.fetch('synthetic_secret_marker'), role].join('-')
  end

  def self.now = Time.iso8601(INPUTS.fetch('now'))
  def self.user_id = INPUTS.fetch('user_id')
  def self.path = File.join(ROOT, 'jwt_vectors.json')

  def self.encode(vectors)
    rows = vectors.fetch('vectors').map do |row|
      token = row['token']
      token.is_a?(String) && token.count('.') == 2 ? row.merge('token' => token.split('.', -1)) : row
    end
    "#{JSON.pretty_generate({ 'synthetic' => true, 'vectors' => rows })}\n"
  end
end
