# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Geocoding::RateLimiter do
  def config_for(host, rps: nil, provider: :photon)
    Geocoding::Config.new(source: :user, provider: provider, host: host, rps: rps)
  end

  let(:fast) { config_for('photon.example.com', rps: 10) }

  before do
    allow(described_class).to receive(:sleep)
    Sidekiq.redis { |redis| redis.keys("#{described_class::NAMESPACE}:*").each { |key| redis.del(key) } }
  end

  describe '.throttle' do
    it 'returns the block value' do
      expect(described_class.throttle(fast) { :result }).to eq(:result)
    end

    it 'runs unthrottled when no rate is configured' do
      described_class.throttle(config_for('photon.example.com')) { :ok }

      expect(described_class).not_to have_received(:sleep)
    end

    it 'does not wait for the first request in an empty bucket' do
      described_class.throttle(fast) { :ok }

      expect(described_class).not_to have_received(:sleep)
    end

    it 'spaces the next request by one interval' do
      described_class.throttle(fast) { :ok }
      described_class.throttle(fast) { :ok }

      expect(described_class).to have_received(:sleep).with(be_within(0.02).of(0.1)).once
    end

    it 'spaces each further request by another interval' do
      3.times { described_class.throttle(fast) { :ok } }

      expect(described_class).to have_received(:sleep).with(be_within(0.02).of(0.2)).once
    end

    it 'still runs the block when redis is unreachable' do
      allow(Sidekiq).to receive(:redis).and_raise(Redis::CannotConnectError)
      allow(Rails.logger).to receive(:warn)

      expect(described_class.throttle(fast) { :ok }).to eq(:ok)
      expect(Rails.logger).to have_received(:warn).with(/RateLimiter/)
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
      alice = config_for('photon.example.com', rps: 10)
      bob = config_for('photon.example.com', rps: 10)

      described_class.throttle(alice) { :ok }
      described_class.throttle(bob) { :ok }

      expect(described_class).to have_received(:sleep).once
    end

    it 'shares one bucket across port and path spellings of the same host' do
      described_class.throttle(config_for('photon.example.com', rps: 10)) { :ok }
      described_class.throttle(config_for('photon.example.com:8080/photon', rps: 10)) { :ok }

      expect(described_class).to have_received(:sleep).once
    end
  end

  describe 'wait budget' do
    let(:slow) { config_for('photon.example.com', rps: 0.5) }

    it 'gives up its place in line rather than hanging a web request' do
      allow(Sidekiq).to receive(:server?).and_return(false)

      described_class.throttle(slow) { :ok }
      before_slot = Sidekiq.redis { |redis| redis.get(described_class.key_for(slow)) }
      expect(described_class.throttle(slow) { :ok }).to eq(:ok)
      after_slot = Sidekiq.redis { |redis| redis.get(described_class.key_for(slow)) }

      expect(described_class).not_to have_received(:sleep)
      expect(after_slot).to eq(before_slot)
    end

    it 'waits out the interval inside a worker' do
      allow(Sidekiq).to receive(:server?).and_return(true)

      described_class.throttle(slow) { :ok }
      described_class.throttle(slow) { :ok }

      expect(described_class).to have_received(:sleep).with(be_within(0.05).of(2.0)).once
    end

    it 'warns when a worker has to wait a long time' do
      allow(Sidekiq).to receive(:server?).and_return(true)
      allow(Rails.logger).to receive(:warn)
      crawl = config_for('photon.example.com', rps: 0.1)

      3.times { described_class.throttle(crawl) { :ok } }

      expect(Rails.logger).to have_received(:warn).with(/RateLimiter/).at_least(:once)
    end
  end

  describe '.key_for' do
    it 'expires the reservation so a stale slot cannot pin the bucket forever' do
      described_class.throttle(fast) { :ok }

      ttl = Sidekiq.redis { |redis| redis.ttl(described_class.key_for(fast)) }

      expect(ttl).to be > 0
    end
  end
end
