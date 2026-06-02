# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Point, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:import).optional }
    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:country).optional }
    it { is_expected.to belong_to(:visit).optional }
    it { is_expected.to belong_to(:track).optional }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:timestamp) }
    it { is_expected.to validate_presence_of(:lonlat) }
  end

  describe 'callbacks' do
    describe '#set_country' do
      let(:point) { build(:point, lonlat: 'POINT(-79.85581250721961 15.854775993302411)') }
      let(:country) { create(:country) }

      it 'sets the country' do
        expect(Country).to receive(:containing_point).with(-79.85581250721961, 15.854775993302411).and_return(country)

        point.save!

        expect(point.country_id).to eq(country.id)
      end
    end
  end

  describe 'scopes' do
    describe '.reverse_geocoded' do
      let(:point) { create(:point, :reverse_geocoded) }
      let(:point_without_address) { create(:point, city: nil, country: nil) }

      it 'returns points with reverse geocoded address' do
        expect(described_class.reverse_geocoded).to eq([point])
      end
    end

    describe '.not_reverse_geocoded' do
      let!(:point) { create(:point, country: 'Country', city: 'City', reverse_geocoded_at: Time.current) }
      let!(:point_without_address) { create(:point, city: nil, country: nil, reverse_geocoded_at: nil) }

      it 'returns points without reverse geocoded address' do
        # Trigger creation of both points
        point
        point_without_address

        result = described_class.not_reverse_geocoded
        expect(result).to include(point_without_address)
        expect(result).not_to include(point)
      end
    end

    describe 'anomaly scopes' do
      let(:user) { create(:user) }
      let!(:normal_point) { create(:point, user: user, anomaly: nil) }
      let!(:false_point) { create(:point, user: user, anomaly: false) }
      let!(:anomaly_point) { create(:point, user: user, anomaly: true) }

      describe '.not_anomaly' do
        it 'includes points with anomaly nil' do
          expect(described_class.not_anomaly).to include(normal_point)
        end

        it 'includes points with anomaly false' do
          expect(described_class.not_anomaly).to include(false_point)
        end

        it 'excludes points with anomaly true' do
          expect(described_class.not_anomaly).not_to include(anomaly_point)
        end
      end

      describe '.anomaly' do
        it 'includes only anomaly points' do
          expect(described_class.anomaly).to contain_exactly(anomaly_point)
        end
      end
    end
  end

  describe 'methods' do
    describe '#recorded_at' do
      let(:point) { create(:point, timestamp: 1_554_317_696) }

      it 'returns recorded at time' do
        expect(point.recorded_at).to eq(Time.zone.at(1_554_317_696))
      end
    end

    describe '#async_reverse_geocode' do
      let(:point) { build(:point) }

      def clear_dedup_key(point_id)
        Sidekiq.redis { |r| r.del(Point.geocode_dedup_key(point_id)) }
      end

      before do
        allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true)
        allow(DawarichSettings).to receive(:store_geodata?).and_return(true)
        Sidekiq.redis { |r| r.keys('geocode:enq:*').each { |k| r.del(k) } }
      end

      it 'enqueues ReverseGeocodeJob with correct arguments' do
        point.save
        clear_dedup_key(point.id)

        expect { point.async_reverse_geocode }.to have_enqueued_job(ReverseGeocodingJob)
          .with('Point', point.id, force: false)
      end

      context 'when point is imported' do
        let(:point) { build(:point, import_id: 1) }

        it 'enqueues ReverseGeocodeJob' do
          expect { point.async_reverse_geocode }.to have_enqueued_job(ReverseGeocodingJob)
        end
      end

      context 'when reverse geocoding is disabled' do
        before do
          allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(false)
        end

        it 'does not enqueue ReverseGeocodeJob' do
          expect { point.save }.not_to have_enqueued_job(ReverseGeocodingJob)
        end
      end

      context 'when called twice for the same point' do
        it 'only enqueues a single job (dedup)' do
          point.save

          expect { point.async_reverse_geocode }.not_to have_enqueued_job(ReverseGeocodingJob)
        end

        it 'sets a 24h-TTL Redis key for the point id' do
          point.save

          ttl = Sidekiq.redis { |r| r.ttl(Point.geocode_dedup_key(point.id)) }
          expect(ttl).to be > 0
          expect(ttl).to be <= 86_400
        end
      end

      context 'with force: true' do
        it 'enqueues even when dedup key is set' do
          point.save

          expect { point.async_reverse_geocode(force: true) }
            .to have_enqueued_job(ReverseGeocodingJob)
            .with('Point', point.id, force: true)
        end

        it 'clears the dedup key so subsequent non-force calls can re-claim' do
          point.save

          point.async_reverse_geocode(force: true)

          expect(Sidekiq.redis { |r| r.call('EXISTS', Point.geocode_dedup_key(point.id)) }).to eq(0)
        end
      end

      context 'with different points' do
        it 'enqueues a separate job per point' do
          point.save
          other_point = build(:point)

          expect { other_point.save }
            .to have_enqueued_job(ReverseGeocodingJob).with('Point', kind_of(Integer), force: false)
        end
      end

      context 'when perform_later raises after the SETNX claim' do
        it 'releases the dedup key so a retry can re-claim' do
          point.save
          clear_dedup_key(point.id)
          allow(ReverseGeocodingJob).to receive(:perform_later).and_raise(StandardError, 'queue down')

          expect { point.async_reverse_geocode }.to raise_error(StandardError, 'queue down')
          expect(Sidekiq.redis { |r| r.call('EXISTS', Point.geocode_dedup_key(point.id)) }).to eq(0)
        end
      end
    end

    describe '#lon' do
      let(:point) { create(:point, lonlat: 'POINT(1 2)') }

      it 'returns longitude' do
        expect(point.lon).to eq(1)
      end
    end

    describe '#lat' do
      let(:point) { create(:point, lonlat: 'POINT(1 2)') }

      it 'returns latitude' do
        expect(point.lat).to eq(2)
      end
    end
  end

  describe '#broadcast_coordinates privacy zone suppression' do
    let(:user) { create(:user) }
    let(:tag) { create(:tag, :privacy_zone, user: user, privacy_radius_meters: 500) }
    let(:place) { create(:place, user: user, latitude: 52.444, longitude: 13.500) }

    before do
      create(:tagging, tag: tag, taggable: place)
      user.settings['live_map_enabled'] = true
      user.save!
    end

    context 'when a point is inside a privacy zone' do
      it 'does not broadcast to PointsChannel' do
        expect do
          create(:point, user: user, lonlat: 'POINT(13.500 52.444)')
        end.not_to have_broadcasted_to(user).from_channel(PointsChannel)
      end
    end

    context 'when a point is outside all privacy zones' do
      it 'broadcasts to PointsChannel' do
        expect do
          create(:point, user: user, lonlat: 'POINT(13.700 52.600)')
        end.to have_broadcasted_to(user).from_channel(PointsChannel)
      end
    end
  end

  describe '.outside_privacy_zones' do
    it 'excludes points inside the user\'s privacy zones' do
      user = create(:user)
      tag = create(:tag, :privacy_zone, user: user, privacy_radius_meters: 1000)
      place = create(:place, user: user, latitude: 52.444, longitude: 13.500)
      create(:tagging, tag: tag, taggable: place)
      inside = create(:point, user: user, lonlat: 'POINT(13.500 52.444)')
      outside = create(:point, user: user, lonlat: 'POINT(13.700 52.600)')

      result = Point.outside_privacy_zones(user)

      expect(result).to include(outside)
      expect(result).not_to include(inside)
    end
  end

  describe '.dedup_key' do
    let(:timestamp) { Time.zone.at(1_700_000_000) }

    it 'collapses different WKT strings that parse to the same doubles' do
      a = { lonlat: 'POINT(-0.1278 51.5074)', timestamp: timestamp, user_id: 1 }
      b = { lonlat: 'POINT(-0.12780000 51.50740000)', timestamp: timestamp, user_id: 1 }

      expect(described_class.dedup_key(a)).to eq(described_class.dedup_key(b))
    end

    it 'distinguishes points whose doubles actually differ' do
      a = { lonlat: 'POINT(-0.1278 51.5074)', timestamp: timestamp, user_id: 1 }
      b = { lonlat: 'POINT(-0.1279 51.5074)', timestamp: timestamp, user_id: 1 }

      expect(described_class.dedup_key(a)).not_to eq(described_class.dedup_key(b))
    end

    it 'distinguishes points by timestamp and user_id' do
      base = { lonlat: 'POINT(-0.1278 51.5074)', timestamp: timestamp, user_id: 1 }

      expect(described_class.dedup_key(base))
        .not_to eq(described_class.dedup_key(base.merge(timestamp: timestamp + 1)))
      expect(described_class.dedup_key(base))
        .not_to eq(described_class.dedup_key(base.merge(user_id: 2)))
    end

    it 'ignores SRID prefix in EWKT and yields the same key as plain WKT' do
      plain = { lonlat: 'POINT(-0.1278 51.5074)', timestamp: timestamp, user_id: 1 }
      ewkt  = { lonlat: 'SRID=4326;POINT(-0.1278 51.5074)', timestamp: timestamp, user_id: 1 }

      expect(described_class.dedup_key(plain)).to eq(described_class.dedup_key(ewkt))
    end

    it 'extracts lon and lat from POINT Z (3D form) without folding altitude into the key' do
      flat = { lonlat: 'POINT(-0.1278 51.5074)', timestamp: timestamp, user_id: 1 }
      threed = { lonlat: 'POINT Z (-0.1278 51.5074 100)', timestamp: timestamp, user_id: 1 }

      expect(described_class.dedup_key(flat)).to eq(described_class.dedup_key(threed))
    end

    it 'handles southern-hemisphere negative lat/lon' do
      a = { lonlat: 'POINT(-68.1193 -16.4897)', timestamp: timestamp, user_id: 1 }
      b = { lonlat: 'POINT(-68.11930 -16.48970)', timestamp: timestamp, user_id: 1 }

      expect(described_class.dedup_key(a)).to eq(described_class.dedup_key(b))
    end
  end
end
