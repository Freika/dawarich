# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TrackSerializer do
  describe '#call' do
    let(:user) { create(:user) }
    let(:track) { create(:track, user: user) }
    let(:serializer) { described_class.new(track) }

    subject(:serialized_track) { serializer.call }

    it 'returns a hash with all required attributes' do
      expect(serialized_track).to be_a(Hash)
      expect(serialized_track.keys).to contain_exactly(
        :id, :start_at, :end_at, :distance, :avg_speed, :duration,
        :elevation_gain, :elevation_loss, :elevation_max, :elevation_min, :original_path
      )
    end

    it 'serializes the track ID correctly' do
      expect(serialized_track[:id]).to eq(track.id)
    end

    it 'formats start_at as ISO8601 timestamp' do
      expect(serialized_track[:start_at]).to eq(track.start_at.iso8601)
      expect(serialized_track[:start_at]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
    end

    it 'formats end_at as ISO8601 timestamp' do
      expect(serialized_track[:end_at]).to eq(track.end_at.iso8601)
      expect(serialized_track[:end_at]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
    end

    it 'converts distance to integer' do
      expect(serialized_track[:distance]).to eq(track.distance.to_i)
      expect(serialized_track[:distance]).to be_a(Integer)
    end

    it 'converts avg_speed to float' do
      expect(serialized_track[:avg_speed]).to eq(track.avg_speed.to_f)
      expect(serialized_track[:avg_speed]).to be_a(Float)
    end

    it 'serializes duration as numeric value' do
      expect(serialized_track[:duration]).to eq(track.duration)
      expect(serialized_track[:duration]).to be_a(Numeric)
    end

    it 'serializes elevation_gain as numeric value' do
      expect(serialized_track[:elevation_gain]).to eq(track.elevation_gain)
      expect(serialized_track[:elevation_gain]).to be_a(Numeric)
    end

    it 'serializes elevation_loss as numeric value' do
      expect(serialized_track[:elevation_loss]).to eq(track.elevation_loss)
      expect(serialized_track[:elevation_loss]).to be_a(Numeric)
    end

    it 'serializes elevation_max as numeric value' do
      expect(serialized_track[:elevation_max]).to eq(track.elevation_max)
      expect(serialized_track[:elevation_max]).to be_a(Numeric)
    end

    it 'serializes elevation_min as numeric value' do
      expect(serialized_track[:elevation_min]).to eq(track.elevation_min)
      expect(serialized_track[:elevation_min]).to be_a(Numeric)
    end

    it 'converts original_path to string' do
      expect(serialized_track[:original_path]).to eq(track.original_path.to_s)
      expect(serialized_track[:original_path]).to be_a(String)
    end

    context 'with decimal distance values' do
      let(:track) { create(:track, user: user, distance: 1234.56) }

      it 'truncates distance to integer' do
        expect(serialized_track[:distance]).to eq(1234)
      end
    end

    context 'with decimal avg_speed values' do
      let(:track) { create(:track, user: user, avg_speed: 25.75) }

      it 'converts avg_speed to float' do
        expect(serialized_track[:avg_speed]).to eq(25.75)
      end
    end

    context 'with different original_path formats' do
      let(:track) { create(:track, user: user, original_path: 'LINESTRING(0 0, 1 1, 2 2)') }

      it 'converts geometry to WKT string format' do
        expect(serialized_track[:original_path]).to match(/LINESTRING \(0(\.0)? 0(\.0)?, 1(\.0)? 1(\.0)?, 2(\.0)? 2(\.0)?\)/)
        expect(serialized_track[:original_path]).to be_a(String)
      end
    end

    context 'with zero values' do
      let(:track) do
        create(:track, user: user,
               distance: 0,
               avg_speed: 0.0,
               duration: 0,
               elevation_gain: 0,
               elevation_loss: 0,
               elevation_max: 0,
               elevation_min: 0)
      end

      it 'handles zero values correctly' do
        expect(serialized_track[:distance]).to eq(0)
        expect(serialized_track[:avg_speed]).to eq(0.0)
        expect(serialized_track[:duration]).to eq(0)
        expect(serialized_track[:elevation_gain]).to eq(0)
        expect(serialized_track[:elevation_loss]).to eq(0)
        expect(serialized_track[:elevation_max]).to eq(0)
        expect(serialized_track[:elevation_min]).to eq(0)
      end
    end

    context 'with very large values' do
      let(:track) do
        create(:track, user: user,
               distance: 1_000_000.0,
               avg_speed: 999.99,
               duration: 86_400, # 24 hours in seconds
               elevation_gain: 10_000,
               elevation_loss: 8_000,
               elevation_max: 5_000,
               elevation_min: 0)
      end

      it 'handles large values correctly' do
        expect(serialized_track[:distance]).to eq(1_000_000)
        expect(serialized_track[:avg_speed]).to eq(999.99)
        expect(serialized_track[:duration]).to eq(86_400)
        expect(serialized_track[:elevation_gain]).to eq(10_000)
        expect(serialized_track[:elevation_loss]).to eq(8_000)
        expect(serialized_track[:elevation_max]).to eq(5_000)
        expect(serialized_track[:elevation_min]).to eq(0)
      end
    end

    context 'with different timestamp formats' do
      let(:start_time) { Time.current }
      let(:end_time) { start_time + 1.hour }
      let(:track) { create(:track, user: user, start_at: start_time, end_at: end_time) }

      it 'formats timestamps consistently' do
        expect(serialized_track[:start_at]).to eq(start_time.iso8601)
        expect(serialized_track[:end_at]).to eq(end_time.iso8601)
      end
    end
  end

  describe '#initialize' do
    let(:track) { create(:track) }

    it 'accepts a track parameter' do
      expect { described_class.new(track) }.not_to raise_error
    end

    it 'stores the track instance' do
      serializer = described_class.new(track)
      expect(serializer.instance_variable_get(:@track)).to eq(track)
    end
  end
end
