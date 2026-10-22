# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Dawarich::ReverseGeocodingLimits do
  describe '.for' do
    it 'leaves the global limit off when the provider has no rate limit' do
      expect(described_class.for(pool: 10, rps: nil, override: nil)[:limit]).to be_nil
    end

    it 'keeps one thread of every process free for the other queues' do
      expect(described_class.for(pool: 10, rps: nil, override: nil)[:process_limit]).to eq(9)
      expect(described_class.for(pool: 3, rps: nil, override: nil)[:process_limit]).to eq(2)
    end

    it 'never lets a single-thread process strand the queue' do
      expect(described_class.for(pool: 1, rps: nil, override: nil)[:process_limit]).to eq(1)
    end

    it 'caps the queue at the threads a rate limit can keep busy' do
      expect(described_class.for(pool: 10, rps: 1.0, override: nil)[:limit]).to eq(1)
      expect(described_class.for(pool: 10, rps: 7.5, override: nil)[:limit]).to eq(8)
      expect(described_class.for(pool: 10, rps: 0.2, override: nil)[:limit]).to eq(1)
    end

    it 'lets REVERSE_GEOCODING_CONCURRENCY win over the rate limit' do
      expect(described_class.for(pool: 10, rps: 1.0, override: 6)[:limit]).to eq(6)
      expect(described_class.for(pool: 10, rps: nil, override: 6)[:limit]).to eq(6)
    end

    it 'floors an override of zero at one' do
      expect(described_class.for(pool: 10, rps: nil, override: 0)[:limit]).to eq(1)
    end
  end

  describe '.configure!' do
    let(:config) { Sidekiq::Config.new(concurrency: 10) }

    before { allow(Geocoding::Config).to receive(:for).and_return(instance_double(Geocoding::Config, rps: rps)) }

    context 'when the provider has no rate limit' do
      let(:rps) { nil }

      it 'hands limit_fetch no global limit and a per-process one' do
        described_class.configure!(config, override: nil)

        expect(config[:limits]).to include('reverse_geocoding' => nil)
        expect(config[:process_limits]).to eq('reverse_geocoding' => 9)
      end
    end

    context 'when the provider is rate limited' do
      let(:rps) { 1.0 }

      it 'hands limit_fetch the rate-derived limit' do
        described_class.configure!(config, override: nil)

        expect(config[:limits]).to eq('reverse_geocoding' => 1)
      end
    end

    context 'when the geocoding config cannot be read' do
      let(:rps) { nil }

      it 'still configures the queue as if the provider were unlimited' do
        allow(Geocoding::Config).to receive(:for).and_raise(ActiveRecord::ConnectionNotEstablished)

        described_class.configure!(config, override: nil)

        expect(config[:limits]).to include('reverse_geocoding' => nil)
        expect(config[:process_limits]).to eq('reverse_geocoding' => 9)
      end
    end

    context 'when other queues already have limits' do
      let(:rps) { nil }

      it 'keeps them' do
        config[:limits] = { 'imports' => 2 }

        described_class.configure!(config, override: nil)

        expect(config[:limits]).to include('imports' => 2)
      end
    end
  end
end
