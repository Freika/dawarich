# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('app-phoenix/scripts/parity/rate_limit_fixture_support')

RSpec.describe 'Phoenix rate-limit corpus' do
  let(:corpus) { JSON.parse(RateLimitFixtureSupport::PATH.read) }

  it 'names every rack-attack throttle in declaration order with the limit and period Phoenix enforces' do
    expect(corpus.fetch('throttles')).to eq(RateLimitFixtureSupport.throttle_table)
    expect(corpus.fetch('plan_limits')).to eq(Rack::Attack.api_rate_limits)
    expect(corpus.fetch('blocklists')).to eq(Rack::Attack.blocklists.keys)
    expect(corpus.fetch('max_json_body')).to eq(MAX_JSON_BODY_BYTES)
  end
end
