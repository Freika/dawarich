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
end
