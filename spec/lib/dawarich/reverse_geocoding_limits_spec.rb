# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Dawarich::ReverseGeocodingLimits do
  let(:queue) { Sidekiq::Queue['reverse_geocoding'] }

  around do |example|
    saved = ENV.fetch('REVERSE_GEOCODING_CONCURRENCY', nil)
    ENV.delete('REVERSE_GEOCODING_CONCURRENCY')
    example.run
  ensure
    saved.nil? ? ENV.delete('REVERSE_GEOCODING_CONCURRENCY') : ENV['REVERSE_GEOCODING_CONCURRENCY'] = saved
    queue.limit = nil
    queue.process_limit = nil
  end

  describe '.limit' do
    it 'leaves the global limit off when the provider has no rate limit' do
      expect(described_class.limit(rps: nil, override: nil)).to be_nil
    end

    it 'caps the queue at the threads a rate limit can keep busy' do
      expect(described_class.limit(rps: 1.0, override: nil)).to eq(1)
      expect(described_class.limit(rps: 7.5, override: nil)).to eq(8)
      expect(described_class.limit(rps: 0.2, override: nil)).to eq(1)
    end

    it 'lets REVERSE_GEOCODING_CONCURRENCY win over the rate limit' do
      expect(described_class.limit(rps: 1.0, override: 6)).to eq(6)
      expect(described_class.limit(rps: nil, override: 6)).to eq(6)
    end

    it 'floors an override of zero at one' do
      expect(described_class.limit(rps: nil, override: 0)).to eq(1)
    end
  end

  describe '.process_limit' do
    it 'keeps one thread of every process free for the other queues' do
      expect(described_class.process_limit(10)).to eq(9)
      expect(described_class.process_limit(3)).to eq(2)
    end

    it 'never lets a single-thread process strand the queue' do
      expect(described_class.process_limit(1)).to eq(1)
    end
  end

  describe '.configure!' do
    let(:config) { Sidekiq::Config.new(concurrency: 10) }

    it 'hands limit_fetch no global limit and a per-process one when the provider is unlimited' do
      configure_instance_geocoding(photon_api_host: 'photon.example.org')

      described_class.configure!(config)

      expect(config[:limits]).to include('reverse_geocoding' => nil)
      expect(config[:process_limits]).to eq('reverse_geocoding' => 9)
    end

    it 'hands limit_fetch the rate-derived limit' do
      configure_instance_geocoding(photon_api_host: 'photon.komoot.io')

      described_class.configure!(config)

      expect(config[:limits]).to eq('reverse_geocoding' => 1)
    end

    it 'reads REVERSE_GEOCODING_CONCURRENCY' do
      ENV['REVERSE_GEOCODING_CONCURRENCY'] = '6'

      described_class.configure!(config)

      expect(config[:limits]).to eq('reverse_geocoding' => 6)
    end

    it 'still configures the queue as if the provider were unlimited when its config cannot be read' do
      allow(Geocoding::Config).to receive(:for).and_raise(ActiveRecord::ConnectionNotEstablished)

      described_class.configure!(config)

      expect(config[:limits]).to include('reverse_geocoding' => nil)
      expect(config[:process_limits]).to eq('reverse_geocoding' => 9)
    end

    it 'keeps limits other queues already have' do
      config[:limits] = { 'imports' => 2 }

      described_class.configure!(config)

      expect(config[:limits]).to include('imports' => 2)
    end

    it 'logs the limits it applied' do
      allow(Rails.logger).to receive(:info)

      described_class.configure!(config)

      expect(Rails.logger).to have_received(:info).with(/limit=none process_limit=9/)
    end
  end

  describe '.refresh!' do
    it 'rewrites the global limit from the current provider' do
      queue.limit = nil
      configure_instance_geocoding(photon_api_host: 'photon.komoot.io')

      described_class.refresh!

      expect(queue.limit).to eq(1)
    end

    it 'lifts the limit when the provider stops being rate limited' do
      queue.limit = 1
      configure_instance_geocoding(photon_api_host: 'photon.example.org')

      described_class.refresh!

      expect(queue.limit).to be_nil
    end
  end
end
