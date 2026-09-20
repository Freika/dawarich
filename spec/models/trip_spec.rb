# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Trip, type: :model do
  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:started_at) }
    it { is_expected.to validate_presence_of(:ended_at) }

    context 'date range validation' do
      let(:user) { create(:user) }

      it 'is valid when started_at is before ended_at' do
        trip = build(:trip, user: user, started_at: 1.day.ago, ended_at: Time.current)
        expect(trip).to be_valid
      end

      it 'is invalid when started_at is after ended_at' do
        trip = build(:trip, user: user, started_at: Time.current, ended_at: 1.day.ago)
        expect(trip).not_to be_valid
        expect(trip.errors[:ended_at]).to include('must be after start date')
      end

      it 'is invalid when started_at equals ended_at' do
        time = Time.current
        trip = build(:trip, user: user, started_at: time, ended_at: time)
        expect(trip).not_to be_valid
        expect(trip.errors[:ended_at]).to include('must be after start date')
      end

      it 'is valid when both dates are blank during initialization' do
        trip = Trip.new(user: user, name: 'Test Trip')
        expect(trip.errors[:ended_at]).to be_empty
      end
    end
  end

  describe 'associations' do
    it { is_expected.to belong_to(:user) }
  end

  describe 'callbacks' do
    let(:user) { create(:user) }
    let(:trip) { create(:trip, :with_points, user:) }

    context 'when the trip is created' do
      let(:trip) { build(:trip, :with_points, user:) }

      it 'enqueues the calculation jobs' do
        expect { trip.save }.to have_enqueued_job(Trips::CalculateAllJob)
      end

      it 'enqueues calculations for an ongoing trip' do
        trip.started_at = 1.day.ago
        trip.ended_at = 1.day.from_now

        expect { trip.save }.to have_enqueued_job(Trips::CalculateAllJob)
      end
    end
  end

  describe '#photo_previews' do
    let(:photo_data) do
      [
        {
          'id' => '123',
          'latitude' => 35.6762,
          'longitude' => 139.6503,
          'localDateTime' => '2024-01-01T03:00:00.000Z',
          'type' => 'photo',
          'exifInfo' => {
            'orientation' => '3'
          }
        },
        {
          'id' => '456',
          'latitude' => 40.7128,
          'longitude' => -74.0060,
          'localDateTime' => '2024-01-02T01:00:00.000Z',
          'type' => 'photo',
          'exifInfo' => {
            'orientation' => '6'
          }
        },
        {
          'id' => '789',
          'latitude' => 40.7128,
          'longitude' => -74.0060,
          'localDateTime' => '2024-01-02T02:00:00.000Z',
          'type' => 'photo',
          'exifInfo' => {
            'orientation' => '6'
          }
        }
      ]
    end
    let(:user) { create(:user, settings: settings) }
    let(:trip) { create(:trip, user:) }
    let(:expected_photos) do
      [
        {
          id: '456',
          url: "/api/v1/photos/456/thumbnail.jpg?api_key=#{user.api_key}&source=immich",
          source: 'immich',
          orientation: 'portrait',
          taken_at: '2024-01-02T01:00:00.000Z'
        },
        {
          id: '789',
          url: "/api/v1/photos/789/thumbnail.jpg?api_key=#{user.api_key}&source=immich",
          source: 'immich',
          orientation: 'portrait',
          taken_at: '2024-01-02T02:00:00.000Z'
        }
      ]
    end

    before do
      allow_any_instance_of(Immich::RequestPhotos).to receive(:call).and_return(photo_data)
    end

    context 'when Immich integration is not configured' do
      let(:settings) { {} }

      it 'returns an empty array' do
        expect(trip.photo_previews).to eq([])
      end
    end

    context 'when Immich integration is configured' do
      let(:settings) do
        {
          immich_url: 'https://immich.example.com',
          immich_api_key: '1234567890'
        }
      end

      it 'returns the photos' do
        expect(trip.photo_previews).to include(expected_photos[0])
        expect(trip.photo_previews).to include(expected_photos[1])
        expect(trip.photo_previews.size).to eq(2)
      end
    end
  end

  describe '#photos_by_day' do
    let(:user) { create(:user) }
    let(:trip) { create(:trip, user: user) }

    context 'when there are photos with timestamps' do
      let(:photos) do
        [
          { id: 1, url: '/p/1', source: 'immich', orientation: 'landscape', taken_at: '2024-11-27T23:30:00Z' },
          { id: 2, url: '/p/2', source: 'immich', orientation: 'landscape', taken_at: '2024-11-29T08:00:00Z' },
          { id: 3, url: '/p/3', source: 'immich', orientation: 'landscape', taken_at: nil }
        ]
      end

      before do
        allow(Trips::Photos).to receive(:new).with(trip, user)
                                             .and_return(instance_double(Trips::Photos, call: photos))
      end

      it 'buckets a photo by its UTC instant converted into the given timezone, not its UTC date' do
        result = trip.photos_by_day('Europe/Berlin')

        expect(result.keys).to contain_exactly(Date.new(2024, 11, 28), Date.new(2024, 11, 29))
        expect(result[Date.new(2024, 11, 28)].map { _1[:id] }).to eq([1])
        expect(result[Date.new(2024, 11, 29)].map { _1[:id] }).to eq([2])
      end

      it 'excludes photos with a blank taken_at' do
        result = trip.photos_by_day('Europe/Berlin')

        expect(result.values.flatten.map { _1[:id] }).not_to include(3)
      end
    end

    context 'when a photo has a naive (no-offset) timestamp' do
      let(:photos) do
        [{ id: 9, url: '/p/9', source: 'immich', orientation: 'landscape', taken_at: '2024-11-30T00:30:00' }]
      end

      before do
        allow(Trips::Photos).to receive(:new).with(trip, user)
                                             .and_return(instance_double(Trips::Photos, call: photos))
      end

      it 'buckets it as wall-clock time in the given timezone' do
        result = trip.photos_by_day('Europe/Berlin')

        expect(result.keys).to contain_exactly(Date.new(2024, 11, 30))
        expect(result[Date.new(2024, 11, 30)].map { _1[:id] }).to eq([9])
      end
    end

    context 'when there are no photos' do
      before do
        allow(Trips::Photos).to receive(:new).with(trip, user)
                                             .and_return(instance_double(Trips::Photos, call: []))
      end

      it 'returns an empty hash' do
        expect(trip.photos_by_day('Europe/Berlin')).to eq({})
      end
    end
  end

  describe '#plan_geojson' do
    let(:trip) { create(:trip) }

    it 'maps located stops per day with their order, a line within each day, stays and loose places' do
      first = trip.planned_days.create!(date: trip.started_at.to_date, position: 1)
      second = trip.planned_days.create!(date: trip.started_at.to_date + 1, position: 2)
      first.planned_stops.create!(name: 'Museum', position: 1, latitude: 51.31, longitude: 12.41)
      first.planned_stops.create!(name: 'No coordinates', position: 2)
      first.planned_stops.create!(name: 'Panorama', position: 3, latitude: 51.32, longitude: 12.39)
      second.planned_stops.create!(name: 'Station', position: 1, latitude: 51.35, longitude: 12.38)
      trip.planned_accommodations.create!(name: 'Hotel', latitude: 51.34, longitude: 12.37)
      trip.planned_unplanned_places.create!(name: 'Market', position: 1, latitude: 51.33, longitude: 12.36)

      features = trip.plan_geojson[:features]

      stops = features.select { |f| f[:properties][:kind] == 'stop' }
      expect(stops.map { |f| f[:properties].values_at(:name, :day, :number) }).to eq(
        [['Museum', 0, 1], ['Panorama', 0, 3], ['Station', 1, 1]]
      )
      expect(stops.first[:geometry]).to eq(type: 'Point', coordinates: [12.41, 51.31])
      routes = features.select { |f| f[:properties][:kind] == 'route' }
      expect(routes.map { |f| [f[:properties][:day], f[:geometry][:coordinates]] }).to eq(
        [[0, [[12.41, 51.31], [12.39, 51.32]]]]
      )
      expect(features.map { |f| f[:properties][:kind] }).to include('stay', 'unplanned')
    end

    it 'has nothing to draw without coordinates' do
      day = trip.planned_days.create!(date: trip.started_at.to_date, position: 1)
      day.planned_stops.create!(name: 'Somewhere', position: 1)

      expect(trip.plan_geojson).to be_nil
    end
  end

  describe 'device handoffs' do
    let(:user) { create(:user) }
    let(:trip) { create(:trip, user:, started_at: Time.utc(2026, 1, 1), ended_at: Time.utc(2026, 1, 5)) }

    def recorded_point(device, hour, longitude)
      create(:point, user:, tracker_id: device, timestamp: trip.started_at.to_i + hour.hours,
                     lonlat: "POINT(#{longitude} 52)")
    end

    it 'keeps both remainders when recordings share their handoff timestamp' do
      first = [recorded_point('phone', 1, 13), recorded_point('phone', 2, 13.01), recorded_point('phone', 3, 13.02)]
      recorded_point('watch', 3, 14)
      last = recorded_point('watch', 4, 13.03)

      trip.calculate_path
      trip.calculate_distance

      expect(trip.primary_device_points.pluck(:id)).to eq(first.map(&:id) + [last.id])
      expected_windows = [
        { tracker_id: 'phone', start_at: first.first.timestamp, end_at: first.last.timestamp },
        { tracker_id: 'watch', start_at: first.last.timestamp + 1, end_at: last.timestamp }
      ]
      expect(trip.primary_device_windows).to eq(expected_windows)
      expect(trip.path.points.map(&:x)).to eq([13, 13.01, 13.02, 13.03])
      expect(trip.distance).to be_within(1).of(Point.total_distance(first + [last], :m))
    end

    it 'keeps unique days before and after a busier device records' do
      early = recorded_point('watch', 1, 13)
      recorded_point('watch', 25, 14)
      late = recorded_point('watch', 73, 13.04)
      primary = [recorded_point('phone', 24, 13.01), recorded_point('phone', 25, 13.02),
                 recorded_point('phone', 26, 13.03), recorded_point('phone', 27, 13.035)]

      trip.calculate_path
      trip.calculate_distance
      expected = [early] + primary + [late]

      expect(trip.primary_device_points.pluck(:id)).to eq(expected.map(&:id))
      expect(trip.path.points.map(&:x)).to eq([13, 13.01, 13.02, 13.03, 13.035, 13.04])
      expect(trip.distance).to be_within(1).of(Point.total_distance(expected, :m))
      expect(trip.day_stats('UTC').keys).to contain_exactly(Date.new(2026, 1, 1), Date.new(2026, 1, 2),
                                                            Date.new(2026, 1, 4))
    end

    it 'uses source dimensions when selecting overlapping recordings' do
      first = recorded_point('legacy-phone', 1, 13)
      second = recorded_point('legacy-phone', 2, 13.01)
      source = PointSource.create!(digest: SecureRandom.hex(16), tracker_id: 'phone')
      Point.where(id: [first.id, second.id]).update_all(source_id: source.id)
      recorded_point('watch', 2, 14)
      last = recorded_point('watch', 3, 13.02)

      expect(trip.primary_device_points.pluck(:id)).to eq([first.id, second.id, last.id])
    end

    it 'combines unnamed recordings and prefers a named device on a tie' do
      recorded_point(nil, 1, 14)
      recorded_point('', 3, 14.02)
      first = recorded_point('phone', 1, 13)
      last = recorded_point('phone', 3, 13.02)

      expect(trip.primary_device_points.pluck(:id)).to eq([first.id, last.id])
    end
  end

  describe 'Calculateable concern' do
    let(:user) { create(:user) }
    let(:trip) { create(:trip, user: user) }
    let!(:points) do
      [
        create(:point, user: user, lonlat: 'POINT(13.404954 52.520008)', timestamp: trip.started_at.to_i + 1.hour),
        create(:point, user: user, lonlat: 'POINT(13.404955 52.520009)', timestamp: trip.started_at.to_i + 2.hours),
        create(:point, user: user, lonlat: 'POINT(13.404956 52.520010)', timestamp: trip.started_at.to_i + 3.hours)
      ]
    end

    describe '#calculate_distance' do
      it 'stores distance in user preferred unit for Trip model' do
        allow(user).to receive(:safe_settings).and_return(double(distance_unit: 'km'))
        allow(Point).to receive(:total_distance).and_return(2.5) # 2.5 km

        trip.calculate_distance

        expect(trip.distance).to eq(3) # Should be rounded, in km
      end

      it 'calculates distance in the database without loading trip points' do
        create(:point, user: user, lonlat: 'POINT(13.064477 52.398862)', timestamp: trip.started_at.to_i + 4.hours)
        loaded = []
        callback = ->(*, payload) { loaded << payload[:name] if payload[:name] == 'Point Load' }

        ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') { trip.calculate_distance }

        expect(loaded).to be_empty
        expect(trip.distance).to be_within(1_000).of(26_500)
      end
    end

    describe 'with several devices recording at once' do
      let(:berlin_phone) do
        [0, 1, 2, 3].map do |i|
          create(:point, user:, tracker_id: 'phone', lonlat: "POINT(13.40#{i} 52.52)",
                         timestamp: trip.started_at.to_i + 5.hours + (i * 10.minutes))
        end
      end

      before do
        points.each_with_index do |point, i|
          point.update!(tracker_id: 'watch', timestamp: trip.started_at.to_i + 5.hours + ((i + 1) * 5.minutes))
        end
        berlin_phone
        create(:point, user:, tracker_id: 'watch', lonlat: 'POINT(12.38 51.34)',
                       timestamp: trip.started_at.to_i + 5.hours + 5.minutes)
      end

      it 'builds the path from the device that recorded the most points' do
        trip.calculate_path

        expect(trip.path.points.map { |point| point.x.round(3) }).to eq([13.4, 13.401, 13.402, 13.403])
      end

      it 'measures the distance along that device only' do
        trip.calculate_distance

        expect(trip.distance).to be_between(150, 250)
      end

      it 'names the devices worth following' do
        expect(trip.primary_device_windows.map { |window| window[:tracker_id] }.uniq).to eq(['phone'])
      end

      it 'measures each day along the primary device only' do
        stats = trip.day_stats('UTC')

        expect(stats.values.sum { |day| day[:distance_m] }).to be_between(150, 250)
      end
    end

    describe 'with devices recording one after another' do
      before do
        points.each { |point| point.update!(tracker_id: 'gpx-trk-0-seg-0') }
        [0, 1, 2, 3, 4, 5].each do |i|
          create(:point, user:, tracker_id: 'gpx-trk-0-seg-1', lonlat: "POINT(13.40#{i} 52.52)",
                         timestamp: trip.ended_at.to_i - 1.hour + (i * 5.minutes))
        end
      end

      it 'keeps every device whose recording does not overlap another' do
        tracker_ids = trip.primary_device_windows.pluck(:tracker_id).uniq
        expect(tracker_ids).to contain_exactly('gpx-trk-0-seg-0', 'gpx-trk-0-seg-1')
      end

      it 'builds the path from both of them' do
        trip.calculate_path

        expect(trip.path.points.size).to eq(points.size + 6)
      end
    end

    describe '#recalculate_distance!' do
      it 'recalculates and saves the distance' do
        original_distance = trip.distance

        trip.recalculate_distance!

        trip.reload
        expect(trip.distance).not_to eq(original_distance)
      end
    end

    describe '#recalculate_path!' do
      it 'recalculates and saves the path' do
        original_path = trip.path

        trip.recalculate_path!

        trip.reload
        expect(trip.path).not_to eq(original_path)
      end
    end

    describe '#calculate_path' do
      context 'when trip has no points' do
        let(:empty_user) { create(:user) }
        let(:empty_trip) do
          create(:trip, user: empty_user,
                        started_at: 1.year.ago,
                        ended_at: 1.year.ago + 1.day)
        end

        it 'sets path to nil without raising' do
          expect { empty_trip.calculate_path }.not_to raise_error
          expect(empty_trip.path).to be_nil
        end
      end

      context 'when trip has only one point' do
        let(:single_user) { create(:user) }
        let(:single_trip) do
          create(:trip, user: single_user,
                        started_at: 2.years.ago,
                        ended_at: 2.years.ago + 1.day)
        end

        before do
          create(:point, user: single_user,
                         lonlat: 'POINT(10.0 50.0)',
                         timestamp: single_trip.started_at.to_i + 3600)
        end

        it 'sets path to nil without raising' do
          expect { single_trip.calculate_path }.not_to raise_error
          expect(single_trip.path).to be_nil
        end
      end
    end
  end
end
