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
      before { configure_instance_geocoding }

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
      allow(Geocoder).to receive(:search).and_return(
        [double(city: 'City', country: 'Country', data: { 'address' => {} })]
      )
      Sidekiq.redis { |r| r.keys('geocode:enq:*').each { |k| r.del(k) } }
    end

    def key_exists?
      Sidekiq.redis { |r| r.call('EXISTS', Point.geocode_dedup_key(point.id)) } == 1
    end

    context 'when reverse geocoding is enabled' do
      before { configure_instance_geocoding }

      it 'releases the claim after a non-forced run' do
        Sidekiq.redis { |r| r.set(Point.geocode_dedup_key(point.id), 1, ex: Point::GEOCODE_DEDUP_TTL) }

        described_class.new.perform('Point', point.id)

        expect(key_exists?).to be false
      end

      context 'with phoenix.once_claims' do
        before { phoenix_state! }

        it 'releases the claim row after a non-forced run' do
          PhoenixClaims.claim(Point.geocode_dedup_key(point.id), 86_400)

          described_class.new.perform('Point', point.id)

          expect(PhoenixClaims.claim(Point.geocode_dedup_key(point.id), 60)).to be(true)
          expect(key_exists?).to be false
        end
      end

      it 'leaves a concurrent claim intact when the run is forced' do
        Sidekiq.redis { |r| r.set(Point.geocode_dedup_key(point.id), 1, ex: Point::GEOCODE_DEDUP_TTL) }

        described_class.new.perform('Point', point.id, force: true)

        expect(key_exists?).to be true
      end

      it 'does not fail the job when Redis is unreachable during release' do
        geocoded = create(:point, user:, reverse_geocoded_at: Time.current)
        allow(Sidekiq).to receive(:redis).and_raise(ConnectionPool::TimeoutError, 'redis down')

        expect { described_class.new.perform('Point', geocoded.id) }.not_to raise_error
      end
    end

    it 'leaves point claims alone when the job runs for a place' do
      Sidekiq.redis { |r| r.set(Point.geocode_dedup_key(point.id), 1, ex: Point::GEOCODE_DEDUP_TTL) }

      described_class.new.perform('place', point.id)

      expect(key_exists?).to be true
    end
  end

  describe 'Oban-owned forwarding' do
    let(:user) { create(:user) }

    before { configure_instance_geocoding }

    it 'a point forwards once with the job id and keeps the dedupe key' do
      job_owner!('command:geocoding.reverse_point', :oban)
      point = create(:point, user:, reverse_geocoded_at: nil)
      Sidekiq.redis { |r| r.set(Point.geocode_dedup_key(point.id), 1, ex: Point::GEOCODE_DEDUP_TTL) }
      allow(ReverseGeocoding::Points::FetchData).to receive(:new)
      job = described_class.new

      job.perform('Point', point.id)
      job.perform('Point', point.id)

      row = JobOutbox.sole
      expect(row).to have_attributes(payload: { 'user_id' => point.user_id, 'point_ids' => [point.id],
                                                'force' => false }, event_id: job.job_id)
      expect(Sidekiq.redis { |r| r.call('EXISTS', Point.geocode_dedup_key(point.id)) }).to eq(1)
      expect(ReverseGeocoding::Points::FetchData).not_to have_received(:new)
    end

    it 'a place forwards for the lowercase class' do
      job_owner!('command:geocoding.reverse_place', :oban)
      place = create(:place, user:)

      described_class.new.perform('place', place.id)

      row = JobOutbox.sole
      expect(row.payload).to eq('place_id' => place.id)
    end

    it 'a failing forward releases the key and raises' do
      job_owner!('command:geocoding.reverse_point', :oban)
      point = create(:point, user:, reverse_geocoded_at: nil)
      Sidekiq.redis { |r| r.set(Point.geocode_dedup_key(point.id), 1, ex: Point::GEOCODE_DEDUP_TTL) }
      allow(JobCommands).to receive(:forward).and_raise(ActiveRecord::StatementInvalid, 'boom')

      expect { described_class.new.perform('Point', point.id) }.to raise_error(ActiveRecord::StatementInvalid)

      expect(Sidekiq.redis { |r| r.call('EXISTS', Point.geocode_dedup_key(point.id)) }).to eq(0)
    end

    it 'force forwards and never touches the key' do
      job_owner!('command:geocoding.reverse_point', :oban)
      point = create(:point, user:, reverse_geocoded_at: nil)
      foreign_key_owner_id = create(:point, user:, reverse_geocoded_at: nil).id
      Sidekiq.redis { |r| r.set(Point.geocode_dedup_key(foreign_key_owner_id), 1, ex: Point::GEOCODE_DEDUP_TTL) }

      described_class.new.perform('Point', point.id, force: true)

      expect(Sidekiq.redis { |r| r.call('EXISTS', Point.geocode_dedup_key(foreign_key_owner_id)) }).to eq(1)
    end

    it 'a missing record writes no row' do
      job_owner!('command:geocoding.reverse_point', :oban)

      described_class.new.perform('Point', -1)

      expect(JobOutbox.count).to eq(0)
    end

    it 'a disabled config writes no row' do
      job_owner!('command:geocoding.reverse_point', :oban)
      allow(Geocoding::Config).to receive(:for).and_return(instance_double(Geocoding::Config, enabled?: false))
      point = create(:point, user:, reverse_geocoded_at: nil)

      described_class.new.perform('Point', point.id)

      expect(JobOutbox.count).to eq(0)
    end
  end

  describe 'sidekiq options' do
    it 'caps Sidekiq retries at 3 to bound the retry set' do
      expect(described_class.get_sidekiq_options['retry']).to eq(3)
    end
  end

  describe 'with an instance provider configured' do
    let(:owner) { create(:user) }
    let(:point) { create(:point, user: owner) }
    let(:job) { described_class.new }
    let(:fetcher) { instance_double(ReverseGeocoding::Points::FetchData, call: nil) }

    before do
      allow(ReverseGeocoding::Points::FetchData).to receive(:new).and_return(fetcher)
    end

    it 'does not block its own thread to pace komoot' do
      configure_instance_geocoding(photon_api_host: 'photon.komoot.io')
      allow(job).to receive(:sleep)

      job.perform('Point', point.id)

      expect(job).not_to have_received(:sleep)
    end

    it 'returns quietly when the record no longer exists' do
      configure_instance_geocoding

      expect { job.perform('Point', -1) }.not_to raise_error
      expect(ReverseGeocoding::Points::FetchData).not_to have_received(:new)
    end
  end
end
