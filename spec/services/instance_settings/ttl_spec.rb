# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InstanceSettings::Resolver, 'TTL backstop' do
  include ActiveSupport::Testing::TimeHelpers

  around do |example|
    original = ENV.fetch('PHOTON_API_HOST', nil)
    ENV['PHOTON_API_HOST'] = nil
    described_class.reset!
    example.run
  ensure
    ENV['PHOTON_API_HOST'] = original
    described_class.reset!
  end

  # Redis pub/sub has no replay: a message published while a process is
  # reconnecting is gone. Without a TTL that process serves stale config
  # forever with nothing able to detect it.
  it 're-reads once the snapshot passes its TTL even with no message received' do
    expect(described_class.get(:photon_api_host).value).to be_nil

    InstanceSetting.create!(key: 'photon_api_host', value: 'appeared.example.com')

    travel_to(Time.current + described_class::SNAPSHOT_TTL + 1.second) do
      expect(described_class.get(:photon_api_host).value).to eq('appeared.example.com')
    end
  end

  it 'does not re-read inside the TTL window' do
    expect(described_class.get(:photon_api_host).value).to be_nil

    InstanceSetting.create!(key: 'photon_api_host', value: 'appeared.example.com')

    travel_to(Time.current + described_class::SNAPSHOT_TTL - 5.seconds) do
      expect(described_class.get(:photon_api_host).value).to be_nil
    end
  end
end
