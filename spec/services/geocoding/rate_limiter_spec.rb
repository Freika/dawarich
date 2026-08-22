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
end
