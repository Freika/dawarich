# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Geocoding::RateLimiter do
  def config_for(host, rps: nil, provider: :photon, api_key: nil)
    Geocoding::Config.new(source: :user, provider: provider, host: host, rps: rps, api_key: api_key)
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

    it 'skips the block when the wait would exceed the budget' do
      slow = config_for('photon.example.com', rps: 1)
      described_class.throttle(slow) { :ok }

      result = described_class.throttle(slow, max_wait: 0.5) { :never }

      expect(result).to be_nil
      expect(described_class).not_to have_received(:sleep)
    end

    it 'leaves the slot free for callers that can wait' do
      slow = config_for('photon.example.com', rps: 1)
      described_class.throttle(slow) { :ok }
      described_class.throttle(slow, max_wait: 0.5) { :never }

      described_class.throttle(slow) { :ok }

      expect(described_class).to have_received(:sleep).with(be_within(0.05).of(1.0)).once
    end

    it 'runs the block when the wait fits the budget' do
      2.times { described_class.throttle(fast) { :ok } }

      expect(described_class.throttle(fast, max_wait: 0.5) { :ok }).to eq(:ok)
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

  describe 'providers metered per api key' do
    it 'gives two keys on the same host their own bucket' do
      described_class.throttle(config_for('app.chibigeo.com/v1/photon', rps: 10, api_key: 'ck_alice')) { :ok }
      described_class.throttle(config_for('app.chibigeo.com/v1/photon', rps: 10, api_key: 'ck_bob')) { :ok }

      expect(described_class).not_to have_received(:sleep)
    end

    it 'keeps one bucket for two configs sharing a key' do
      2.times do
        described_class.throttle(config_for('app.chibigeo.com/v1/photon', rps: 10, api_key: 'ck_same')) do
          :ok
        end
      end

      expect(described_class).to have_received(:sleep).once
    end

    it 'separates host-less providers by key' do
      described_class.throttle(config_for(nil, rps: 10, provider: :geoapify, api_key: 'alice')) { :ok }
      described_class.throttle(config_for(nil, rps: 10, provider: :geoapify, api_key: 'bob')) { :ok }

      expect(described_class).not_to have_received(:sleep)
    end

    it 'still shares one bucket for komoot when a stale key is left over' do
      # Switching the Photon host from ChibiGeo to komoot keeps the saved key,
      # and komoot meters per IP - splitting on it would let one box exceed the
      # published 1 rps.
      described_class.throttle(config_for('photon.komoot.io', api_key: 'ck_alice_leftover')) { :ok }
      described_class.throttle(config_for('photon.komoot.io', api_key: 'ck_bob_leftover')) { :ok }

      expect(described_class).to have_received(:sleep).once
    end

    it 'does not split a custom self-hosted photon on a key' do
      described_class.throttle(config_for('photon.mine.example.com', rps: 10, api_key: 'a')) { :ok }
      described_class.throttle(config_for('photon.mine.example.com', rps: 10, api_key: 'b')) { :ok }

      expect(described_class).to have_received(:sleep).once
    end

    it 'still shares one bucket for a keyless host metered per ip' do
      2.times { described_class.throttle(config_for('photon.komoot.io')) { :ok } }

      expect(described_class).to have_received(:sleep).once
    end

    it 'does not leak the api key into the bucket name' do
      key = described_class.key_for(config_for('app.chibigeo.com/v1/photon', rps: 10, api_key: 'ck_secret'))

      expect(key).not_to include('ck_secret')
    end
  end

  describe 'concurrent workers' do
    it 'hands every thread its own slot instead of letting two share one' do
      waits = Queue.new
      allow(described_class).to receive(:sleep) { |seconds| waits << seconds }
      crawl = config_for('photon.example.com', rps: 1)

      threads = 5.times.map { Thread.new { described_class.throttle(crawl) { :ok } } }
      threads.each(&:join)

      # Four threads wait (the first goes straight through), and no two waits
      # land on the same slot: 1s, 2s, 3s, 4s in whatever order they queued.
      # A one second interval is chosen so thread scheduling cannot outrun it -
      # at a millisecond interval a loaded runner drags the slot up to now and
      # the waits collapse to zero.
      collected = Array.new(waits.size) { waits.pop }.sort
      expect(collected.size).to eq(4)
      expect(collected.map(&:round)).to eq([1, 2, 3, 4])
    end
  end

  describe 'the shared limiter (GEOCODING_SHARED_RATE_LIMIT)' do
    def stub_flag(value)
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('GEOCODING_SHARED_RATE_LIMIT').and_return(value)
    end

    [nil, 'false', '1'].each do |value|
      it "flag #{value.inspect}: no Redis call and today's pacing" do
        stub_flag(value)
        expect(Sidekiq).not_to receive(:redis)

        2.times { described_class.throttle(fast) { :ok } }
        expect(described_class).to have_received(:sleep).with(be_within(0.02).of(0.1)).once

        slow = config_for('photon.slow.example.com', rps: 1)
        described_class.throttle(slow) { :ok }
        result = described_class.throttle(slow, max_wait: 0.5) { :never }
        expect(result).to be_nil
      end
    end

    context 'with GEOCODING_SHARED_RATE_LIMIT=true' do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('GEOCODING_SHARED_RATE_LIMIT').and_return('true')
      end

      it 'a reservation made by another process delays this one' do
        allow(described_class).to receive(:sleep).and_call_original
        Sidekiq.redis do |redis|
          redis.call('EVAL', described_class::RESERVE_LUA, 1,
                     'geocoding:rate_limit:photon:photon.example.com', 200_000, -1)
        end

        described_class.throttle(config_for('photon.example.com', rps: 5)) { :ok }

        expect(described_class).to have_received(:sleep).with(be_within(0.03).of(0.2)).once
      end

      it 'reservations are spaced across threads' do
        allow(described_class).to receive(:sleep).and_call_original
        config = config_for('photon.threaded.example.com', rps: 5)
        stamps = Queue.new

        threads = 5.times.map do
          Thread.new do
            described_class.throttle(config) { stamps << Process.clock_gettime(Process::CLOCK_MONOTONIC) }
          end
        end
        threads.each(&:join)

        sorted = Array.new(stamps.size) { stamps.pop }.sort
        deltas = sorted.each_cons(2).map { |a, b| b - a }
        expect(deltas).to all(be >= 0.19)
      end

      it 'idle time banks no burst' do
        allow(described_class).to receive(:sleep).and_call_original
        config = config_for('photon.idle.example.com', rps: 5)
        described_class.throttle(config) { :ok }
        sleep 1.0

        first = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        described_class.throttle(config) { :ok }
        described_class.throttle(config) { :ok }
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - first

        expect(elapsed).to be_between(0.19, 0.26)
      end

      it 'max_wait refuses without reserving' do
        config = config_for('photon.maxwait.example.com', rps: 5)
        key = "geocoding:rate_limit:#{described_class.key_for(config)}"
        Sidekiq.redis { |redis| redis.call('EVAL', described_class::RESERVE_LUA, 1, key, 5_000_000, -1) }
        ttl_before = Sidekiq.redis { |redis| redis.call('PTTL', key) }

        result = described_class.throttle(config, max_wait: 1.0) { :never }

        expect(result).to be_nil
        expect(Sidekiq.redis { |redis| redis.call('PTTL', key) }).to be_within(50).of(ttl_before)
      end

      it "the bucket lives in Sidekiq's Redis under the shared key" do
        described_class.throttle(config_for('photon.komoot.io')) { :ok }

        ttl = Sidekiq.redis { |redis| redis.call('PTTL', 'geocoding:rate_limit:photon:photon.komoot.io') }

        expect(ttl).to be_positive
      end

      it 'Redis errors fall back to local pacing' do
        allow(described_class).to receive(:sleep).and_call_original
        allow(Sidekiq).to receive(:redis).and_raise(RedisClient::CannotConnectError)
        allow(Rails.logger).to receive(:warn)
        config = config_for('photon.fallback.example.com', rps: 5)

        first = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        described_class.throttle(config) { :ok }
        described_class.throttle(config) { :ok }
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - first

        expect(Rails.logger).to have_received(:warn).with(/pacing locally/).at_least(:once)
        expect(elapsed).to be >= 0.19
      end

      it 'nil rps never touches Redis' do
        expect(Sidekiq).not_to receive(:redis)

        described_class.throttle(config_for('photon.example.com')) { :ok }
      end
    end
  end
end
