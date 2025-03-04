# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::SmartDetect do
  let(:user) { create(:user) }
  let(:start_at) { DateTime.new(2025, 3, 1, 12, 0, 0) }
  let(:end_at) { DateTime.new(2025, 3, 1, 13, 0, 0) }

  let(:geocoder_struct) do
    Struct.new(:lon, :lat, :data) do
      def latitude
        lat
      end

      def longitude
        lon
      end

      def data # rubocop:disable Metrics/MethodLength
        {
          "geometry": {
            "coordinates": [
              lon,
              lat
            ],
            "type": 'Point'
          },
          "type": 'Feature',
          "properties": {
            "osm_id": 681_354_082,
            "extent": [
              lon,
              lat,
              lon + 0.0001,
              lat + 0.0001
            ],
            "country": 'Russia',
            "city": 'Moscow',
            "countrycode": 'RU',
            "postcode": '103265',
            "type": 'street',
            "osm_type": 'W',
            "osm_key": 'highway',
            "district": 'Tverskoy',
            "osm_value": 'pedestrian',
            "name": 'проезд Воскресенские Ворота',
            "state": 'Moscow'
          }
        }
      end
    end
  end

  let(:geocoder_response) do
    [
      geocoder_struct.new(0, 0, geocoder_struct.new(0, 0).data[:features]),
      geocoder_struct.new(0.00001, 0.00001, geocoder_struct.new(0.00001, 0.00001).data[:features]),
      geocoder_struct.new(0.00002, 0.00002, geocoder_struct.new(0.00002, 0.00002).data[:features])
    ]
  end

  subject(:detector) { described_class.new(user, start_at:, end_at:) }

  before do
    # Create a hash mapping coordinates to mock results
    geocoder_results = {
      [40.123, -74.456] => [
        double(
          data: {
            'address' => {
              'road' => 'First Street',
              'city' => 'First City'
              # other address components
            },
            'name' => 'First Place'
          }
        )
      ],
      [41.789, -73.012] => [
        double(
          data: {
            'address' => {
              'road' => 'Second Street',
              'city' => 'Second City'
              # other address components
            },
            'name' => 'Second Place'
          }
        )
      ]
    }

    # Set up default stub
    allow(Geocoder).to receive(:search) do |coords|
      geocoder_results[coords] || []
    end
  end

  describe '#call' do
    context 'when there are no points' do
      it 'returns an empty array' do
        expect(detector.call).to eq([])
      end
    end

    context 'with a simple visit' do
      let!(:points) do
        [
          create(:point, user:, lonlat: 'POINT(0 0)', timestamp: start_at),
          create(:point, user:, lonlat: 'POINT(0.00001 0.00001)', timestamp: start_at + 5.minutes),
          create(:point, user:, lonlat: 'POINT(0.00002 0.00002)', timestamp: start_at + 10.minutes)
        ]
      end

      it 'creates a visit' do
        expect { detector.call }.to change(Visit, :count).by(1)
      end

      it 'assigns points to the visit' do
        visits = detector.call
        expect(visits.first.points).to match_array(points)
      end

      it 'sets correct visit attributes' do
        visit = detector.call.first

        expect(visit).to have_attributes(
          started_at: be_within(1.second).of(start_at),
          ended_at: be_within(1.second).of(start_at + 10.minutes),
          duration: be_within(1).of(10), # 10 minutes
          status: 'suggested'
        )
      end
    end

    context 'with points containing geodata' do
      let(:geodata) do
        {
          'features' => [
            {
              'properties' => {
                'type' => 'shop',
                'name' => 'Coffee Shop',
                'street' => 'Main Street',
                'city' => 'Example City',
                'state' => 'Example State'
              }
            }
          ]
        }
      end

      let!(:points) do
        [
          create(:point, user:, lonlat: 'POINT(0 0)', timestamp: start_at, geodata:),
          create(:point, user:, lonlat: 'POINT(0.00001 0.00001)', timestamp: start_at + 5.minutes,
                geodata:),
          create(:point, user:, lonlat: 'POINT(0.00002 0.00002)', timestamp: start_at + 10.minutes,
                geodata:)
        ]
      end

      it 'suggests a name based on geodata' do
        visit = detector.call.first

        expect(visit.name).to eq('Coffee Shop, Main Street, Example City, Example State')
      end

      context 'with mixed feature types' do
        let(:mixed_geodata1) do
          {
            'features' => [
              {
                'properties' => {
                  'type' => 'shop',
                  'name' => 'Coffee Shop',
                  'street' => 'Main Street'
                }
              }
            ]
          }
        end

        let(:mixed_geodata2) do
          {
            'features' => [
              {
                'properties' => {
                  'type' => 'restaurant',
                  'name' => 'Burger Place',
                  'street' => 'Main Street'
                }
              }
            ]
          }
        end

        let!(:points) do
          [
            create(:point, user:, lonlat: 'POINT(0 0)',
                   timestamp: start_at + 5.minutes,
                   geodata: mixed_geodata1),
            create(:point, user:, lonlat: 'POINT(0.00001 0.00001)',
                   timestamp: start_at + 10.minutes,
                   geodata: mixed_geodata1),
            create(:point, user:, lonlat: 'POINT(0.00002 0.00002)',
                   timestamp: start_at + 15.minutes,
                   geodata: mixed_geodata2)
          ]
        end

        it 'uses the most common feature type and name' do
          visit = detector.call.first
          expect(visit).not_to be_nil
          expect(visit.name).to eq('Coffee Shop, Main Street')
        end
      end

      context 'with empty or invalid geodata' do
        let!(:points) do
          [
            create(:point, user:, lonlat: 'POINT(0 0)', timestamp: start_at,
                  geodata: {}),
            create(:point, user:, lonlat: 'POINT(0.00001 0.00001)', timestamp: start_at + 5.minutes,
                  geodata: {}),
            create(:point, user:, lonlat: 'POINT(0.00002 0.00002)', timestamp: start_at + 10.minutes,
                  geodata: { 'features' => [] })
          ]
        end

        it 'falls back to Unknown Location' do
          visit = detector.call.first
          expect(visit.name).to eq('Suggested place')
        end
      end
    end

    context 'with multiple visits to the same place' do
      let(:start_at) { DateTime.new(2025, 3, 1, 12, 0, 0) }
      let(:end_at) { DateTime.new(2025, 3, 1, 14, 0, 0) } # Extended to 2 hours

      let!(:morning_points) do
        [
          create(:point, user:, lonlat: 'POINT(0 0)',
                 timestamp: start_at + 10.minutes),
          create(:point, user:, lonlat: 'POINT(0.00001 0.00001)',
                 timestamp: start_at + 15.minutes),
          create(:point, user:, lonlat: 'POINT(0.00002 0.00002)',
                 timestamp: start_at + 20.minutes)
        ]
      end

      let!(:afternoon_points) do
        [
          create(:point, user:, lonlat: 'POINT(0 0)',
                 timestamp: start_at + 90.minutes), # 1.5 hours later
          create(:point, user:, lonlat: 'POINT(0.00001 0.00001)',
                 timestamp: start_at + 95.minutes),
          create(:point, user:, lonlat: 'POINT(0.00002 0.00002)',
                 timestamp: start_at + 100.minutes)
        ]
      end

      it 'assigns correct points to each visit' do
        visits = detector.call

        expect(visits.count).to eq(2)
        expect(visits.first.points).to match_array(morning_points)
        expect(visits.last.points).to match_array(afternoon_points)
      end
    end

    context 'with a known area' do
      let!(:area) { create(:area, user:, latitude: 0, longitude: 0, radius: 100, name: 'Home') }
      let!(:points) do
        [
          create(:point, user:, lonlat: 'POINT(0 0)', timestamp: start_at + 10.minutes),
          create(:point, user:, lonlat: 'POINT(0.00001 0.00001)', timestamp: start_at + 15.minutes),
          create(:point, user:, lonlat: 'POINT(0.00002 0.00002)', timestamp: start_at + 20.minutes)
        ]
      end

      it 'associates the visit with the area' do
        visits = detector.call

        visit = visits.first
        expect(visit).not_to be_nil
        expect(visit.area).to eq(area)
        expect(visit.name).to eq('Home')
      end

      context 'with geodata present' do
        let(:geodata) do
          {
            'features' => [
              {
                'properties' => {
                  'type' => 'shop',
                  'name' => 'Coffee Shop',
                  'street' => 'Main Street'
                }
              }
            ]
          }
        end

        let!(:points) do
          [
            create(:point, user:, lonlat: 'POINT(0 0)',
                   timestamp: start_at + 10.minutes,
                   geodata: geodata),
            create(:point, user:, lonlat: 'POINT(0.00001 0.00001)',
                   timestamp: start_at + 15.minutes,
                   geodata: geodata),
            create(:point, user:, lonlat: 'POINT(0.00002 0.00002)',
                   timestamp: start_at + 20.minutes,
                   geodata: geodata)
          ]
        end

        it 'prefers area name over geodata' do
          visits = detector.call

          visit = visits.first
          expect(visit).not_to be_nil
          expect(visit.name).to eq('Home')
        end
      end
    end

    context 'with points too far apart' do
      let!(:points) do
        [
          create(:point, user:, lonlat: 'POINT(0 0)', timestamp: start_at),
          create(:point, user:, lonlat: 'POINT(0 0)', timestamp: start_at + 5.minutes),
          create(:point, user:, lonlat: 'POINT(0 0)', timestamp: start_at + 10.minutes),

          create(:point, user:, lonlat: 'POINT(10 10)', timestamp: start_at + 15.minutes),
          create(:point, user:, lonlat: 'POINT(10 10)', timestamp: start_at + 20.minutes),
          create(:point, user:, lonlat: 'POINT(10 10)', timestamp: start_at + 25.minutes)
        ]
      end

      it 'creates separate visits' do
        expect { detector.call }.to change(Visit, :count).by(2)
      end
    end

    context 'with points too far apart in time' do
      # Use a wider time range to ensure all points are within the detector's window
      let(:end_at) { DateTime.new(2025, 3, 1, 15, 0, 0) }

      let!(:points) do
        [
          # First visit with more points to ensure it's significant
          create(:point, user:, lonlat: 'POINT(0 0)',
                 timestamp: DateTime.new(2025, 3, 1, 12, 0, 0)),
          create(:point, user:, lonlat: 'POINT(0 0)',
                 timestamp: DateTime.new(2025, 3, 1, 12, 5, 0)),
          create(:point, user:, lonlat: 'POINT(0 0)',
                 timestamp: DateTime.new(2025, 3, 1, 12, 10, 0)),

          # Second visit - with a gap of 40 minutes (beyond MAXIMUM_VISIT_GAP)
          create(:point, user:, lonlat: 'POINT(0 0)',
                 timestamp: DateTime.new(2025, 3, 1, 12, 50, 0)),
          create(:point, user:, lonlat: 'POINT(0 0)',
                 timestamp: DateTime.new(2025, 3, 1, 12, 55, 0)),
          create(:point, user:, lonlat: 'POINT(0 0)',
                 timestamp: DateTime.new(2025, 3, 1, 13, 0, 0))
        ]
      end

      it 'creates separate visits' do
        expect { detector.call }.to change(Visit, :count).by(2)
      end
    end

    context 'with an existing place' do
      let!(:place) { create(:place, latitude: 0, longitude: 0, name: 'Coffee Shop') }
      let!(:points) do
        [
          create(:point, user:, lonlat: 'POINT(0 0)',
             timestamp: start_at + 10.minutes),
          create(:point, user:, lonlat: 'POINT(0.00001 0.00001)',
             timestamp: start_at + 15.minutes),
          create(:point, user:, lonlat: 'POINT(0.00002 0.00002)',
             timestamp: start_at + 20.minutes)
        ]
      end

      it 'associates the visit with the place' do
        visits = detector.call
        visit = visits.first

        expect(visit).not_to be_nil
        expect(visit.place).to eq(place)
        expect(visit.name).to eq('Coffee Shop')
      end

      context 'with different geodata' do
        let(:geodata) do
          {
            'features' => [
              {
                'properties' => {
                  'type' => 'restaurant',
                  'name' => 'Burger Place',
                  'street' => 'Main Street'
                }
              }
            ]
          }
        end

        let!(:points) do
          [
            create(:point, user:, lonlat: 'POINT(0 0)',
                   timestamp: start_at + 10.minutes,
                   geodata: geodata),
            create(:point, user:, lonlat: 'POINT(0.00001 0.00001)',
                   timestamp: start_at + 15.minutes,
                   geodata: geodata),
            create(:point, user:, lonlat: 'POINT(0.00002 0.00002)',
                   timestamp: start_at + 20.minutes,
                   geodata: geodata)
          ]
        end

        it 'prefers existing place name over geodata' do
          visits = detector.call
          visit = visits.first

          expect(visit).not_to be_nil
          expect(visit.place).to eq(place)
          expect(visit.name).to eq('Coffee Shop')
        end
      end
    end
  end
end
