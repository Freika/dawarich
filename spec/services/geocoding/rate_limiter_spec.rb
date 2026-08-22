# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Geocoding::RateLimiter do
  def config_for(host, rps: nil, provider: :photon)
    Geocoding::Config.new(source: :user, provider: provider, host: host, rps: rps)
  end

  let(:fast) { config_for('photon.example.com', rps: 10) }

  before do
    described_class.reset!
    allow(described_class).to receive(:sleep)
  end

  describe '.throttle' do
    it 'returns the block value' do
      expect(described_class.throttle(fast) { :result }).to eq(:result)
    end

    it 'runs unthrottled when no rate is configured' do
      described_class.throttle(config_for('photon.example.com')) { :ok }

      expect(described_class).not_to have_received(:sleep)
    end

    it 'does not wait for the first request' do
      described_class.throttle(fast) { :ok }

      expect(described_class).not_to have_received(:sleep)
    end

    it 'spaces the next request by one interval' do
      2.times { described_class.throttle(fast) { :ok } }

      expect(described_class).to have_received(:sleep).with(be_within(0.02).of(0.1)).once
    end

    it 'spaces each further request by another interval' do
      3.times { described_class.throttle(fast) { :ok } }

      expect(described_class).to have_received(:sleep).with(be_within(0.02).of(0.2)).once
    end

    it 'does not bank credit while a provider sits idle' do
      quick = config_for('photon.example.com', rps: 100)
      described_class.throttle(quick) { :ok }
      Kernel.sleep(0.05)

      described_class.throttle(quick) { :ok }

      expect(described_class).not_to have_received(:sleep)
    end
  end

  describe 'bucket scope' do
    it 'keeps a separate bucket per host' do
      described_class.throttle(fast) { :ok }
      described_class.throttle(config_for('photon.other.example.com', rps: 10)) { :ok }

      expect(described_class).not_to have_received(:sleep)
    end

    it 'keeps a separate bucket per provider' do
      described_class.throttle(config_for(nil, rps: 10, provider: :geoapify)) { :ok }
      described_class.throttle(config_for(nil, rps: 10, provider: :locationiq)) { :ok }

      expect(described_class).not_to have_received(:sleep)
    end

    it 'shares one bucket across everyone pointed at the same host' do
      described_class.throttle(config_for('photon.example.com', rps: 10)) { :ok }
      described_class.throttle(config_for('photon.example.com', rps: 10)) { :ok }

      expect(described_class).to have_received(:sleep).once
    end

    it 'shares one bucket across port and path spellings of the same host' do
      described_class.throttle(config_for('photon.example.com', rps: 10)) { :ok }
      described_class.throttle(config_for('photon.example.com:8080/photon', rps: 10)) { :ok }

      expect(described_class).to have_received(:sleep).once
    end
  end

  describe 'concurrent workers' do
    it 'hands every thread its own slot instead of letting two share one' do
      waits = Queue.new
      allow(described_class).to receive(:sleep) { |seconds| waits << seconds }
      crawl = config_for('photon.example.com', rps: 1000)

      threads = 5.times.map { Thread.new { described_class.throttle(crawl) { :ok } } }
      threads.each(&:join)

      # Four threads wait (the first goes straight through), and no two waits
      # land on the same slot: 1ms, 2ms, 3ms, 4ms in whatever order they queued.
      collected = Array.new(waits.size) { waits.pop }.sort
      expect(collected.size).to eq(4)
      expect(collected.map { |w| (w * 1000).round }).to eq([1, 2, 3, 4])
    end
  end
end
