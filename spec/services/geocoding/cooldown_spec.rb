# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Geocoding::Cooldown do
  def config_for(host, provider: :photon, api_key: nil)
    Geocoding::Config.new(source: :stored, provider: provider, host: host, api_key: api_key)
  end

  let(:komoot) { config_for('photon.komoot.io') }

  it 'lets lookups go out until a provider refuses one' do
    expect(described_class.active?(komoot)).to be false
    expect(described_class.remaining(komoot)).to be_nil
  end

  it 'pauses lookups for the base duration after a refusal' do
    expect(described_class.start(komoot)).to eq(described_class::BASE_DURATION.to_i)

    expect(described_class.active?(komoot)).to be true
    expect(described_class.remaining(komoot)).to be_within(1).of(described_class::BASE_DURATION.to_i)
  end

  it 'counts refusals that arrive during a running cooldown as one' do
    described_class.start(komoot)

    expect(described_class.start(komoot)).to eq(0)
    expect(described_class.remaining(komoot)).to be_within(1).of(described_class::BASE_DURATION.to_i)
  end

  context 'with a one second base duration' do
    before do
      stub_const('Geocoding::Cooldown::BASE_DURATION', 1.second)
      stub_const('Geocoding::Cooldown::MAX_DURATION', 3.seconds)
    end

    def after_cooldown
      Kernel.sleep(1.1)
    end

    it 'doubles the pause when the provider refuses again after one' do
      described_class.start(komoot)
      after_cooldown

      expect(described_class.active?(komoot)).to be false
      expect(described_class.start(komoot)).to eq(2)
    end

    it 'never pauses for longer than the maximum duration' do
      stub_const('Geocoding::Cooldown::MAX_DURATION', 1.second)
      described_class.start(komoot)
      after_cooldown

      expect(described_class.start(komoot)).to eq(1)
    end

    it 'starts again from the base duration once a lookup has succeeded' do
      described_class.start(komoot)
      after_cooldown
      described_class.clear(komoot)

      expect(described_class.start(komoot)).to eq(1)
    end
  end

  it 'keeps a cooldown to the provider that refused' do
    described_class.start(komoot)

    expect(described_class.active?(config_for('photon.example.com'))).to be false
    expect(described_class.active?(config_for(nil, provider: :geoapify, api_key: 'key'))).to be false
  end

  it 'keeps a cooldown to the api key that ran out on a provider metered per key' do
    described_class.start(config_for(nil, provider: :geoapify, api_key: 'spent'))

    expect(described_class.active?(config_for(nil, provider: :geoapify, api_key: 'fresh'))).to be false
  end

  context 'when Redis is unreachable' do
    before { allow(Sidekiq).to receive(:redis).and_raise(RedisClient::CannotConnectError, 'redis down') }

    it 'lets lookups go out rather than stopping geocoding' do
      expect(described_class.active?(komoot)).to be false
    end

    it 'does not fail the lookup that was refused' do
      expect(described_class.start(komoot)).to eq(0)
      expect { described_class.clear(komoot) }.not_to raise_error
    end
  end
end
