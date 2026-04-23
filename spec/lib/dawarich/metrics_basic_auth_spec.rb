# frozen_string_literal: true

require 'rails_helper'
require 'dawarich/metrics_basic_auth'
require 'rack/mock'

RSpec.describe Dawarich::MetricsBasicAuth do
  let(:inner_app) { ->(_env) { [200, { 'Content-Type' => 'text/plain' }, ['ok']] } }
  let(:middleware) { described_class.new(inner_app) }

  def request(env_overrides = {})
    env = Rack::MockRequest.env_for('/metrics', env_overrides)
    middleware.call(env)
  end

  def basic_auth_header(user, pass)
    encoded = Base64.strict_encode64("#{user}:#{pass}")
    { 'HTTP_AUTHORIZATION' => "Basic #{encoded}" }
  end

  describe 'without credentials' do
    it 'returns 401 with WWW-Authenticate header' do
      status, headers, _body = request
      expect(status).to eq(401)
      expect(headers['WWW-Authenticate']).to match(/\ABasic realm=/)
    end
  end

  describe 'with wrong credentials' do
    it 'returns 401' do
      status, _headers, _body = request(basic_auth_header('wrong', 'creds'))
      expect(status).to eq(401)
    end
  end

  describe 'with correct credentials' do
    it 'delegates to the inner app' do
      status, _headers, body = request(basic_auth_header(METRICS_USERNAME, METRICS_PASSWORD))
      expect(status).to eq(200)
      expect(body.each.to_a.join).to eq('ok')
    end
  end
end
