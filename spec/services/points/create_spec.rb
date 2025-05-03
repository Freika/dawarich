# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::Create do
  describe '#call' do
    let(:user) { create(:user) }
    let(:timestamp) { Time.current }
    let(:params_service) { instance_double(Points::Params) }

    let(:point_params) do
      {
        locations: [
          { lat: 51.5074, lon: -0.1278, timestamp: timestamp.iso8601 },
          { lat: 40.7128, lon: -74.0060, timestamp: (timestamp + 1.hour).iso8601 }
        ]
      }
    end

    let(:processed_data) do
      [
        {
          lonlat: 'POINT(-0.1278 51.5074)',
          timestamp: timestamp,
          user_id: user.id,
          created_at: anything,
          updated_at: anything
        },
        {
          lonlat: 'POINT(-74.006 40.7128)',
          timestamp: timestamp + 1.hour,
          user_id: user.id,
          created_at: anything,
          updated_at: anything
        }
      ]
    end

    let(:upsert_result) do
      [
        Point.new(id: 1, lonlat: 'POINT(-0.1278 51.5074)', timestamp: timestamp),
        Point.new(id: 2, lonlat: 'POINT(-74.006 40.7128)', timestamp: timestamp + 1.hour)
      ]
    end

    it 'processes the points and upserts them to the database' do
      expect(Points::Params).to receive(:new).with(point_params, user.id).and_return(params_service)
      expect(params_service).to receive(:call).and_return(processed_data)
      expect(Point).to receive(:upsert_all)
        .with(
          processed_data,
          unique_by: %i[lonlat timestamp user_id],
          returning: Arel.sql('id, timestamp, ST_X(lonlat::geometry) AS longitude, ST_Y(lonlat::geometry) AS latitude')
        )
        .and_return(upsert_result)

      result = described_class.new(user, point_params).call

      expect(result).to eq(upsert_result)
    end

    context 'with large datasets' do
      let(:many_locations) do
        2001.times.map do |i|
          { lat: 51.5074 + (i * 0.001), lon: -0.1278 - (i * 0.001), timestamp: (timestamp + i.minutes).iso8601 }
        end
      end

      let(:large_params) { { locations: many_locations } }

      let(:large_processed_data) do
        many_locations.map.with_index do |loc, i|
          {
            lonlat: "POINT(#{loc[:lon]} #{loc[:lat]})",
            timestamp: timestamp + i.minutes,
            user_id: user.id,
            created_at: Time.current,
            updated_at: Time.current
          }
        end
      end

      let(:first_batch_result) { 1000.times.map { |i| Point.new(id: i + 1, lonlat: anything, timestamp: anything) } }
      let(:second_batch_result) do
        1000.times.map do |i|
          Point.new(id: i + 1001, lonlat: anything, timestamp: anything)
        end
      end
      let(:third_batch_result) { [Point.new(id: 2001, lonlat: anything, timestamp: anything)] }
      let(:combined_results) { first_batch_result + second_batch_result + third_batch_result }

      before do
        allow(Points::Params).to receive(:new).with(large_params, user.id).and_return(params_service)
        allow(params_service).to receive(:call).and_return(large_processed_data)
        allow(Point).to receive(:upsert_all).exactly(3).times.and_return(first_batch_result, second_batch_result,
                                                                         third_batch_result)
      end

      it 'handles batching for large datasets' do
        result = described_class.new(user, large_params).call

        expect(result.size).to eq(2001)
        expect(result).to eq(combined_results)
      end
    end

    context 'with real data insertion' do
      let(:actual_processed_data) do
        [
          {
            lonlat: 'POINT(-0.1278 51.5074)',
            timestamp: timestamp,
            user_id: user.id,
            created_at: Time.current,
            updated_at: Time.current
          },
          {
            lonlat: 'POINT(-74.006 40.7128)',
            timestamp: timestamp + 1.hour,
            user_id: user.id,
            created_at: Time.current,
            updated_at: Time.current
          }
        ]
      end

      before do
        allow_any_instance_of(Points::Params).to receive(:call).and_return(actual_processed_data)
      end

      it 'creates points in the database' do
        expect do
          described_class.new(user, point_params).call
        end.to change(Point, :count).by(2)

        points = Point.order(:timestamp).last(2)
        expect(points[0].lonlat.x).to be_within(0.0001).of(-0.1278)
        expect(points[0].lonlat.y).to be_within(0.0001).of(51.5074)

        point_time = points[0].timestamp.is_a?(Integer) ? Time.zone.at(points[0].timestamp) : points[0].timestamp
        expect(point_time).to be_within(1.second).of(timestamp)

        expect(points[1].lonlat.x).to be_within(0.0001).of(-74.006)
        expect(points[1].lonlat.y).to be_within(0.0001).of(40.7128)

        point_time = points[1].timestamp.is_a?(Integer) ? Time.zone.at(points[1].timestamp) : points[1].timestamp
        expect(point_time).to be_within(1.second).of(timestamp + 1.hour)
      end
    end

    context 'with GeoJSON example data' do
      let(:geojson_file) { file_fixture('points/geojson_example.json') }
      let(:geojson_data) { JSON.parse(File.read(geojson_file)) }

      let(:expected_processed_data) do
        [
          {
            lonlat: 'POINT(-122.40530871 37.744304130000003)',
            timestamp: Time.parse('2025-01-17T21:03:01Z'),
            user_id: user.id,
            created_at: Time.current,
            updated_at: Time.current
          },
          {
            lonlat: 'POINT(-122.40518926999999 37.744513759999997)',
            timestamp: Time.parse('2025-01-17T21:03:02Z'),
            user_id: user.id,
            created_at: Time.current,
            updated_at: Time.current
          }
        ]
      end

      let(:all_processed_data) do
        6.times.map do |i|
          if i < 2
            expected_processed_data[i]
          else
            {
              lonlat: 'POINT(-122.0 37.0)',
              timestamp: Time.parse('2025-01-17T21:03:03Z') + i.minutes,
              user_id: user.id,
              created_at: Time.current,
              updated_at: Time.current
            }
          end
        end
      end

      let(:expected_results) do
        all_processed_data.map.with_index do |data, i|
          expected_time = data[:timestamp].to_i
          Point.new(
            id: i + 1,
            lonlat: data[:lonlat],
            timestamp: expected_time
          )
        end
      end

      before do
        allow(Points::Params).to receive(:new).with(geojson_data, user.id).and_return(params_service)
        allow(params_service).to receive(:call).and_return(all_processed_data)
        allow(Point).to receive(:upsert_all)
          .with(
            all_processed_data,
            unique_by: %i[lonlat timestamp user_id],
            returning: Arel.sql('id, timestamp, ST_X(lonlat::geometry) AS longitude, ST_Y(lonlat::geometry) AS latitude')
          )
          .and_return(expected_results)
      end

      it 'correctly processes real GeoJSON example data' do
        result = described_class.new(user, geojson_data).call

        expect(result.size).to eq(6)
        expect(result).to eq(expected_results)

        # Compare the x and y coordinates instead of the full point object
        expect(result[0].lonlat.x).to be_within(0.0001).of(-122.40530871)
        expect(result[0].lonlat.y).to be_within(0.0001).of(37.744304130000003)

        # Convert timestamp back to Time for comparison
        time_obj = Time.zone.at(result[0].timestamp)
        expected_time = Time.parse('2025-01-17T21:03:01Z')
        expect(time_obj).to be_within(1.second).of(expected_time)

        expect(result[1].lonlat.x).to be_within(0.0001).of(-122.40518926999999)
        expect(result[1].lonlat.y).to be_within(0.0001).of(37.744513759999997)

        # Convert timestamp back to Time for comparison
        time_obj = Time.zone.at(result[1].timestamp)
        expected_time = Time.parse('2025-01-17T21:03:02Z')
        expect(time_obj).to be_within(1.second).of(expected_time)
      end
    end
  end
end
