# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Geocoding host rules ignore host case' do
  before do
    ENV['PHOTON_API_HOST'] = 'Photon.Komoot.IO'
    ENV['PHOTON_API_USE_HTTPS'] = 'false'
    ENV['REVERSE_GEOCODING_RPS'] = '10'
    InstanceSettings::Resolver.reset!
  end

  it 'forces HTTPS for a TLS-only host written in mixed case' do
    expect(Geocoding::Config.resolved_config.use_https).to be(true)
  end

  it 'holds a mixed-case komoot host to its fixed rate' do
    expect(Geocoding::Config.resolved_config.rps).to eq(Geocoding::RateLimits::KOMOOT_RPS)
  end
end
