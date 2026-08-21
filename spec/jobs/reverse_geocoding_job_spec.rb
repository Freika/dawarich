# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ReverseGeocodingJob, type: :job do
  describe '#perform' do
    subject(:perform) { described_class.new.perform('Point', point.id) }

    let(:point) { create(:point) }

    before do
      allow(Geocoder).to receive(:search).and_return([double(city: 'City', country: 'Country')])
    end

    context 'when reverse geocoding is disabled' do
      before { allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(false) }

      it 'does not update point' do
        expect { perform }.not_to(change { point.reload.city })
      end

      it 'does not call ReverseGeocoding::Points::FetchData' do
        allow(ReverseGeocoding::Points::FetchData).to receive(:new).and_call_original

        perform

        expect(ReverseGeocoding::Points::FetchData).not_to have_received(:new)
      end
    end

    context 'when reverse geocoding is enabled' do
      before { allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true) }

      let(:stubbed_geocoder) { OpenStruct.new(data: { city: 'City', country: 'Country' }) }

      it 'calls Geocoder' do
        allow(Geocoder).to receive(:search).and_return([stubbed_geocoder])
        allow(ReverseGeocoding::Points::FetchData).to receive(:new).and_call_original

        perform

        expect(ReverseGeocoding::Points::FetchData).to have_received(:new).with(point.id, force: false)
      end
    end
  end

  describe 'dedup key release' do
    let(:user) { create(:user) }
    let!(:point) { create(:point, user:, reverse_geocoded_at: nil, city: nil, country: nil) }

    before do
      allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true)
      allow(Geocoder).to receive(:search).and_return(
        [double(city: 'City', country: 'Country', data: { 'address' => {} })]
      )
      Sidekiq.redis { |r| r.keys('geocode:enq:*').each { |k| r.del(k) } }
    end

    def key_exists?
      Sidekiq.redis { |r| r.call('EXISTS', Point.geocode_dedup_key(point.id)) } == 1
    end

    it 'releases the claim after a non-forced run' do
      Sidekiq.redis { |r| r.set(Point.geocode_dedup_key(point.id), 1, ex: Point::GEOCODE_DEDUP_TTL) }

      described_class.new.perform('Point', point.id)

      expect(key_exists?).to be false
    end

    it 'leaves a concurrent claim intact when the run is forced' do
      Sidekiq.redis { |r| r.set(Point.geocode_dedup_key(point.id), 1, ex: Point::GEOCODE_DEDUP_TTL) }

      described_class.new.perform('Point', point.id, force: true)

      expect(key_exists?).to be true
    end

    it 'leaves point claims alone when the job runs for a place' do
      allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(false)
      Sidekiq.redis { |r| r.set(Point.geocode_dedup_key(point.id), 1, ex: Point::GEOCODE_DEDUP_TTL) }

      described_class.new.perform('place', point.id)

      expect(key_exists?).to be true
    end

    it 'does not fail the job when Redis is unreachable during release' do
      geocoded = create(:point, user:, reverse_geocoded_at: Time.current)
      allow(Sidekiq).to receive(:redis).and_raise(ConnectionPool::TimeoutError, 'redis down')

      expect { described_class.new.perform('Point', geocoded.id) }.not_to raise_error
    end
  end

  describe 'sidekiq options' do
    it 'caps Sidekiq retries at 3 to bound the retry set' do
      expect(described_class.get_sidekiq_options['retry']).to eq(3)
    end
  end

  describe 'user mode (no ENV)' do
    let(:owner) { create(:user) }
    let(:point) { create(:point, user: owner) }
    let(:job) { described_class.new }
    let(:fetcher) { instance_double(ReverseGeocoding::Points::FetchData, call: nil) }

    before do
      allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(false)
      allow(ReverseGeocoding::Points::FetchData).to receive(:new).and_return(fetcher)
    end

    it 'fetches data when the owner has an active provider' do
      create(:service_setting, :active, user: owner)

      job.perform('Point', point.id)

      expect(ReverseGeocoding::Points::FetchData).to have_received(:new).with(point.id, force: false)
    end

    it 'skips fetching when the owner has no configuration' do
      job.perform('Point', point.id)

      expect(ReverseGeocoding::Points::FetchData).not_to have_received(:new)
    end

    it 'sleeps for komoot-configured owners' do
      create(:service_setting, :active, user: owner, config: { 'host' => 'photon.komoot.io' })
      allow(job).to receive(:sleep)

      job.perform('Point', point.id)

      expect(job).to have_received(:sleep).with(1)
    end

    it 'does not sleep for other photon hosts' do
      create(:service_setting, :active, user: owner, config: { 'host' => 'photon.example.com' })
      allow(job).to receive(:sleep)

      job.perform('Point', point.id)

      expect(job).not_to have_received(:sleep)
    end

    it 'returns quietly when the record no longer exists' do
      create(:service_setting, :active, user: owner)

      expect { job.perform('Point', -1) }.not_to raise_error
      expect(ReverseGeocoding::Points::FetchData).not_to have_received(:new)
    end
  end
end
