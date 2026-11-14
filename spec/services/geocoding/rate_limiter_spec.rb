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

  describe 'over-limit refusals' do
    let(:komoot) { config_for('photon.komoot.io') }

    def refuse
      described_class.throttle(komoot) { raise Geocoder::OverQueryLimitError }
    end

    def refuse_quietly
      refuse
    rescue Geocoder::OverQueryLimitError
      nil
    end

    it "passes the provider's refusal on to the caller" do
      expect { refuse }.to raise_error(Geocoder::OverQueryLimitError)
    end

    it 'pauses further lookups to that provider' do
      refuse_quietly
      lookups = 0

      expect { described_class.throttle(komoot) { lookups += 1 } }.to raise_error(Geocoding::Cooldown::Active)
      expect(lookups).to eq(0)
    end

    it 'tells an interactive caller the provider is busy instead of raising' do
      refuse_quietly

      expect(described_class.throttle(komoot, max_wait: 1.0) { :never }).to be_nil
    end

    it 'does not send a lookup that was queued behind the refused one' do
      allow(described_class).to receive(:sleep) { Geocoding::Cooldown.start(komoot) }
      described_class.throttle(komoot) { :ok }
      lookups = 0

      expect { described_class.throttle(komoot) { lookups += 1 } }.to raise_error(Geocoding::Cooldown::Active)
      expect(lookups).to eq(0)
    end

    it 'keeps other providers going' do
      refuse_quietly

      expect(described_class.throttle(config_for('photon.example.com', rps: 10)) { :ok }).to eq(:ok)
    end

    it 'pauses for the base duration again once the provider has answered' do
      stub_const('Geocoding::Cooldown::BASE_DURATION', 1.second)
      refuse_quietly
      expire_geocoding_cooldown
      described_class.throttle(komoot) { [double(cache_hit: false)] }

      refuse_quietly

      expect(Geocoding::Cooldown.remaining(komoot)).to eq(1)
    end

    it 'keeps doubling the pause when the answer only came from the cache' do
      stub_const('Geocoding::Cooldown::BASE_DURATION', 1.second)
      refuse_quietly
      expire_geocoding_cooldown
      described_class.throttle(komoot) { [double(cache_hit: true)] }

      refuse_quietly

      expect(Geocoding::Cooldown.remaining(komoot)).to eq(2)
    end

    it 'keeps doubling the pause after a lookup that found nothing' do
      stub_const('Geocoding::Cooldown::BASE_DURATION', 1.second)
      refuse_quietly
      expire_geocoding_cooldown
      described_class.throttle(komoot) { [] }

      refuse_quietly

      expect(Geocoding::Cooldown.remaining(komoot)).to eq(2)
    end

    it 'ignores a success that lands after another lookup was refused' do
      described_class.throttle(komoot) do
        Geocoding::Cooldown.start(komoot)
        [double(cache_hit: false)]
      end

      expect(Geocoding::Cooldown.unanswered_refusal?(komoot)).to be true
    end
  end

  describe 'a lookup that reaches the real provider' do
    let(:coordinates) { [rand(10.0..60.0).round(6), rand(10.0..60.0).round(6)] }
    let(:provider_request) { a_request(:get, %r{photon\.test\.example\.com/reverse}) }

    def lookup
      Geocoding::Search.with_config(config: stored_photon, query: coordinates, limit: 1)
    end

    let(:stored_photon) do
      Geocoding::Config.new(source: :stored, provider: :photon, host: 'photon.test.example.com')
    end

    def wait_out_a_refusal
      Geocoding::Cooldown.start(stored_photon)
      expire_geocoding_cooldown
    end

    before do
      use_real_geocoding_lookups
      stub_const('Geocoding::Cooldown::BASE_DURATION', 1.second)
      stub_request(:get, %r{photon\.test\.example\.com/reverse}).to_return(
        status: 200,
        headers: { 'Content-Type' => 'application/json' },
        body: {
          type: 'FeatureCollection',
          features: [{ type: 'Feature', geometry: { type: 'Point', coordinates: coordinates.reverse },
                       properties: { name: 'Somewhere', city: 'Town', country: 'Land' } }]
        }.to_json
      )
    end

    it 'counts the answer from the provider but not its cached repeat' do
      wait_out_a_refusal
      expect(lookup).to be_present
      expect(Geocoding::Cooldown.unanswered_refusal?(stored_photon)).to be false

      wait_out_a_refusal
      expect(lookup).to be_present
      expect(Geocoding::Cooldown.unanswered_refusal?(stored_photon)).to be true
      expect(provider_request).to have_been_made.once
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
