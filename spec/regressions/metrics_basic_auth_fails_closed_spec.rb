# frozen_string_literal: true

require 'rails_helper'
require 'dawarich/metrics_basic_auth'
require 'rack/mock'

# Regression: when METRICS_USERNAME/METRICS_PASSWORD are unset, /metrics must not
# be world-readable. Empty Basic credentials ('Og==' => ':') previously compared
# equal to the nil constants and returned 200.
RSpec.describe 'Dawarich::MetricsBasicAuth fails closed when unset' do
  let(:inner_app) { ->(_env) { [200, { 'Content-Type' => 'text/plain' }, ['ok']] } }
  let(:middleware) { Dawarich::MetricsBasicAuth.new(inner_app) }

  def call_with(header)
    middleware.call(Rack::MockRequest.env_for('/metrics', header))
  end

  before do
    stub_const('METRICS_USERNAME', nil)
    stub_const('METRICS_PASSWORD', nil)
  end

  it 'denies empty credentials (Basic Og==) when both constants are unset' do
    status, = call_with('HTTP_AUTHORIZATION' => "Basic #{Base64.strict_encode64(':')}")
    expect(status).to eq(401)
  end

  it 'denies when no Authorization header is sent' do
    status, = call_with({})
    expect(status).to eq(401)
  end

  it 'denies even a username:password pair while the server side is unset' do
    status, = call_with('HTTP_AUTHORIZATION' => "Basic #{Base64.strict_encode64('a:b')}")
    expect(status).to eq(401)
  end
end
