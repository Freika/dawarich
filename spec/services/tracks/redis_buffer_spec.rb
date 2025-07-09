# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::RedisBuffer do
  let(:user_id) { 123 }
  let(:day) { Date.current }
  let(:buffer) { described_class.new(user_id, day) }

  describe '#initialize' do
    it 'stores user_id and converts day to Date' do
      expect(buffer.user_id).to eq(user_id)
      expect(buffer.day).to eq(day)
      expect(buffer.day).to be_a(Date)
    end

    it 'handles string date input' do
      buffer = described_class.new(user_id, '2024-01-15')
      expect(buffer.day).to eq(Date.parse('2024-01-15'))
    end

    it 'handles Time input' do
      time = Time.current
      buffer = described_class.new(user_id, time)
      expect(buffer.day).to eq(time.to_date)
    end
  end

  describe '#store' do
    let(:user) { create(:user) }
    let!(:points) do
      [
        create(:point, user: user, lonlat: 'POINT(-74.0060 40.7128)', timestamp: 1.hour.ago.to_i),
        create(:point, user: user, lonlat: 'POINT(-74.0070 40.7130)', timestamp: 30.minutes.ago.to_i)
      ]
    end

    it 'stores points in Redis cache' do
      expect(Rails.cache).to receive(:write).with(
        "track_buffer:#{user_id}:#{day.strftime('%Y-%m-%d')}",
        anything,
        expires_in: 7.days
      )

      buffer.store(points)
    end

    it 'serializes points correctly' do
      buffer.store(points)

      stored_data = Rails.cache.read("track_buffer:#{user_id}:#{day.strftime('%Y-%m-%d')}")

      expect(stored_data).to be_an(Array)
      expect(stored_data.size).to eq(2)

      first_point = stored_data.first
      expect(first_point[:id]).to eq(points.first.id)
      expect(first_point[:timestamp]).to eq(points.first.timestamp)
      expect(first_point[:lat]).to eq(points.first.lat)
      expect(first_point[:lon]).to eq(points.first.lon)
      expect(first_point[:user_id]).to eq(points.first.user_id)
    end

    it 'does nothing when given empty array' do
      expect(Rails.cache).not_to receive(:write)
      buffer.store([])
    end

    it 'logs debug message when storing points' do
      expect(Rails.logger).to receive(:debug).with(
        "Stored 2 points in buffer for user #{user_id}, day #{day}"
      )

      buffer.store(points)
    end
  end

  describe '#retrieve' do
    context 'when buffer exists' do
      let(:stored_data) do
        [
          {
            id: 1,
            lonlat: 'POINT(-74.0060 40.7128)',
            timestamp: 1.hour.ago.to_i,
            lat: 40.7128,
            lon: -74.0060,
            altitude: 100,
            velocity: 5.0,
            battery: 80,
            user_id: user_id
          },
          {
            id: 2,
            lonlat: 'POINT(-74.0070 40.7130)',
            timestamp: 30.minutes.ago.to_i,
            lat: 40.7130,
            lon: -74.0070,
            altitude: 105,
            velocity: 6.0,
            battery: 75,
            user_id: user_id
          }
        ]
      end

      before do
        Rails.cache.write(
          "track_buffer:#{user_id}:#{day.strftime('%Y-%m-%d')}",
          stored_data
        )
      end

      it 'returns the stored point data' do
        result = buffer.retrieve

        expect(result).to eq(stored_data)
        expect(result.size).to eq(2)
      end
    end

    context 'when buffer does not exist' do
      it 'returns empty array' do
        result = buffer.retrieve
        expect(result).to eq([])
      end
    end

    context 'when Redis read fails' do
      before do
        allow(Rails.cache).to receive(:read).and_raise(StandardError.new('Redis error'))
      end

      it 'returns empty array and logs error' do
        expect(Rails.logger).to receive(:error).with(
          "Failed to retrieve buffered points for user #{user_id}, day #{day}: Redis error"
        )

        result = buffer.retrieve
        expect(result).to eq([])
      end
    end
  end

  describe '#clear' do
    before do
      Rails.cache.write(
        "track_buffer:#{user_id}:#{day.strftime('%Y-%m-%d')}",
        [{ id: 1, timestamp: 1.hour.ago.to_i }]
      )
    end

    it 'deletes the buffer from cache' do
      buffer.clear

      expect(Rails.cache.read("track_buffer:#{user_id}:#{day.strftime('%Y-%m-%d')}")).to be_nil
    end

    it 'logs debug message' do
      expect(Rails.logger).to receive(:debug).with(
        "Cleared buffer for user #{user_id}, day #{day}"
      )

      buffer.clear
    end
  end

  describe '#exists?' do
    context 'when buffer exists' do
      before do
        Rails.cache.write(
          "track_buffer:#{user_id}:#{day.strftime('%Y-%m-%d')}",
          [{ id: 1 }]
        )
      end

      it 'returns true' do
        expect(buffer.exists?).to be true
      end
    end

    context 'when buffer does not exist' do
      it 'returns false' do
        expect(buffer.exists?).to be false
      end
    end
  end

  describe 'buffer key generation' do
    it 'generates correct Redis key format' do
      expected_key = "track_buffer:#{user_id}:#{day.strftime('%Y-%m-%d')}"

      # Access private method for testing
      actual_key = buffer.send(:buffer_key)

      expect(actual_key).to eq(expected_key)
    end

    it 'handles different date formats consistently' do
      date_as_string = '2024-03-15'
      date_as_date = Date.parse(date_as_string)

      buffer1 = described_class.new(user_id, date_as_string)
      buffer2 = described_class.new(user_id, date_as_date)

      expect(buffer1.send(:buffer_key)).to eq(buffer2.send(:buffer_key))
    end
  end

  describe 'integration test' do
    let(:user) { create(:user) }
    let!(:points) do
      [
        create(:point, user: user, lonlat: 'POINT(-74.0060 40.7128)', timestamp: 2.hours.ago.to_i),
        create(:point, user: user, lonlat: 'POINT(-74.0070 40.7130)', timestamp: 1.hour.ago.to_i)
      ]
    end

    it 'stores and retrieves points correctly' do
      # Store points
      buffer.store(points)
      expect(buffer.exists?).to be true

      # Retrieve points
      retrieved_points = buffer.retrieve
      expect(retrieved_points.size).to eq(2)

      # Verify data integrity
      expect(retrieved_points.first[:id]).to eq(points.first.id)
      expect(retrieved_points.last[:id]).to eq(points.last.id)

      # Clear buffer
      buffer.clear
      expect(buffer.exists?).to be false
      expect(buffer.retrieve).to eq([])
    end
  end
end
