# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::TimeChunker do
  let(:user) { create(:user) }
  let(:chunker) { described_class.new(user, **options) }
  let(:options) { {} }

  describe '#initialize' do
    it 'sets default values' do
      expect(chunker.user).to eq(user)
      expect(chunker.start_at).to be_nil
      expect(chunker.end_at).to be_nil
      expect(chunker.chunk_size).to eq(1.day)
      expect(chunker.buffer_size).to eq(6.hours)
    end

    it 'accepts custom options' do
      start_time = 1.week.ago
      end_time = Time.current

      custom_chunker = described_class.new(
        user,
        start_at: start_time,
        end_at: end_time,
        chunk_size: 2.days,
        buffer_size: 2.hours
      )

      expect(custom_chunker.start_at).to eq(start_time)
      expect(custom_chunker.end_at).to eq(end_time)
      expect(custom_chunker.chunk_size).to eq(2.days)
      expect(custom_chunker.buffer_size).to eq(2.hours)
    end
  end

  describe '#call' do
    context 'when user has no points' do
      it 'returns empty array' do
        expect(chunker.call).to eq([])
      end
    end

    context 'when start_at is after end_at' do
      let(:options) { { start_at: Time.current, end_at: 1.day.ago } }

      it 'returns empty array' do
        expect(chunker.call).to eq([])
      end
    end

    context 'with user points' do
      let!(:point1) { create(:point, user: user, timestamp: 3.days.ago.to_i) }
      let!(:point2) { create(:point, user: user, timestamp: 2.days.ago.to_i) }
      let!(:point3) { create(:point, user: user, timestamp: 1.day.ago.to_i) }

      context 'with both start_at and end_at provided' do
        let(:start_time) { 3.days.ago }
        let(:end_time) { 1.day.ago }
        let(:options) { { start_at: start_time, end_at: end_time } }

        it 'creates chunks for the specified range' do
          chunks = chunker.call

          expect(chunks).not_to be_empty
          expect(chunks.first[:start_time]).to be >= start_time
          expect(chunks.last[:end_time]).to be <= end_time
        end

        it 'creates chunks with buffer zones' do
          chunks = chunker.call

          chunk = chunks.first
          # Buffer zones should be at or beyond chunk boundaries (may be constrained by global boundaries)
          expect(chunk[:buffer_start_time]).to be <= chunk[:start_time]
          expect(chunk[:buffer_end_time]).to be >= chunk[:end_time]

          # Verify buffer timestamps are consistent
          expect(chunk[:buffer_start_timestamp]).to eq(chunk[:buffer_start_time].to_i)
          expect(chunk[:buffer_end_timestamp]).to eq(chunk[:buffer_end_time].to_i)
        end

        it 'includes required chunk data structure' do
          chunks = chunker.call

          chunk = chunks.first
          expect(chunk).to include(
            :chunk_id,
            :start_timestamp,
            :end_timestamp,
            :buffer_start_timestamp,
            :buffer_end_timestamp,
            :start_time,
            :end_time,
            :buffer_start_time,
            :buffer_end_time
          )

          expect(chunk[:chunk_id]).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
        end
      end

      context 'with only start_at provided' do
        let(:start_time) { 2.days.ago }
        let(:options) { { start_at: start_time } }

        it 'creates chunks from start_at to current time' do
          # Capture current time before running to avoid precision issues
          end_time_before = Time.current
          chunks = chunker.call
          end_time_after = Time.current

          expect(chunks).not_to be_empty
          expect(chunks.first[:start_time]).to be >= start_time
          # Allow for some time drift during test execution
          expect(chunks.last[:end_time]).to be_between(end_time_before, end_time_after + 1.second)
        end
      end

      context 'with only end_at provided' do
        let(:options) { { end_at: 1.day.ago } }

        it 'creates chunks from first point to end_at' do
          chunks = chunker.call

          expect(chunks).not_to be_empty
          expect(chunks.first[:start_time]).to be >= Time.at(point1.timestamp)
          expect(chunks.last[:end_time]).to be <= 1.day.ago
        end
      end

      context 'with no time range provided' do
        it 'creates chunks for full user point range' do
          chunks = chunker.call

          expect(chunks).not_to be_empty
          expect(chunks.first[:start_time]).to be >= Time.at(point1.timestamp)
          expect(chunks.last[:end_time]).to be <= Time.at(point3.timestamp)
        end
      end

      context 'with custom chunk size' do
        let(:options) { { chunk_size: 12.hours, start_at: 2.days.ago, end_at: Time.current } }

        it 'creates smaller chunks' do
          chunks = chunker.call

          # Should create more chunks with smaller chunk size
          expect(chunks.size).to be > 2

          # Each chunk should be approximately 12 hours
          chunk = chunks.first
          duration = chunk[:end_time] - chunk[:start_time]
          expect(duration).to be <= 12.hours
        end
      end

      context 'with custom buffer size' do
        let(:options) { { buffer_size: 1.hour, start_at: 2.days.ago, end_at: Time.current } }

        it 'creates chunks with smaller buffer zones' do
          chunks = chunker.call

          chunk = chunks.first
          buffer_start_diff = chunk[:start_time] - chunk[:buffer_start_time]
          buffer_end_diff = chunk[:buffer_end_time] - chunk[:end_time]

          expect(buffer_start_diff).to be <= 1.hour
          expect(buffer_end_diff).to be <= 1.hour
        end
      end
    end

    context 'buffer zone boundary handling' do
      let!(:point1) { create(:point, user: user, timestamp: 1.week.ago.to_i) }
      let!(:point2) { create(:point, user: user, timestamp: Time.current.to_i) }
      let(:options) { { start_at: 3.days.ago, end_at: Time.current } }

      it 'does not extend buffers beyond global boundaries' do
        chunks = chunker.call

        chunk = chunks.first
        expect(chunk[:buffer_start_time]).to be >= 3.days.ago
        expect(chunk[:buffer_end_time]).to be <= Time.current
      end
    end

    context 'chunk filtering based on points' do
      let(:options) { { start_at: 1.week.ago, end_at: Time.current } }

      context 'when chunk has no points in buffer range' do
        # Create points only at the very end of the range
        let!(:point) { create(:point, user: user, timestamp: 1.hour.ago.to_i) }

        it 'filters out empty chunks' do
          chunks = chunker.call

          # Should only include chunks that actually have points
          expect(chunks).not_to be_empty
          chunks.each do |chunk|
            # Verify each chunk has points in its buffer range
            points_exist = user.points
              .where(timestamp: chunk[:buffer_start_timestamp]..chunk[:buffer_end_timestamp])
              .exists?
            expect(points_exist).to be true
          end
        end
      end
    end

    context 'timestamp consistency' do
      let!(:point) { create(:point, user: user, timestamp: 1.day.ago.to_i) }
      let(:options) { { start_at: 2.days.ago, end_at: Time.current } }

      it 'maintains timestamp consistency between Time objects and integers' do
        chunks = chunker.call

        chunk = chunks.first
        expect(chunk[:start_timestamp]).to eq(chunk[:start_time].to_i)
        expect(chunk[:end_timestamp]).to eq(chunk[:end_time].to_i)
        expect(chunk[:buffer_start_timestamp]).to eq(chunk[:buffer_start_time].to_i)
        expect(chunk[:buffer_end_timestamp]).to eq(chunk[:buffer_end_time].to_i)
      end
    end

    context 'edge cases' do
      context 'when start_at equals end_at' do
        let(:time_point) { 1.day.ago }
        let(:options) { { start_at: time_point, end_at: time_point } }

        it 'returns empty array' do
          expect(chunker.call).to eq([])
        end
      end

      context 'when user has only one point' do
        let!(:point) { create(:point, user: user, timestamp: 1.day.ago.to_i) }

        it 'creates appropriate chunks' do
          chunks = chunker.call

          # With only one point, start and end times are the same, so no chunks are created
          # This is expected behavior as there's no time range to chunk
          expect(chunks).to be_empty
        end
      end

      context 'when time range is very small' do
        let(:base_time) { 1.day.ago }
        let(:options) { { start_at: base_time, end_at: base_time + 1.hour } }
        let!(:point) { create(:point, user: user, timestamp: base_time.to_i) }

        it 'creates at least one chunk' do
          chunks = chunker.call

          expect(chunks.size).to eq(1)
          expect(chunks.first[:start_time]).to eq(base_time)
          expect(chunks.first[:end_time]).to eq(base_time + 1.hour)
        end
      end
    end
  end

  describe 'private methods' do
    describe '#determine_time_range' do
      let!(:point1) { create(:point, user: user, timestamp: 3.days.ago.to_i) }
      let!(:point2) { create(:point, user: user, timestamp: 1.day.ago.to_i) }

      it 'handles all time range scenarios correctly' do
        test_start_time = 2.days.ago
        test_end_time = Time.current

        # Both provided
        chunker_both = described_class.new(user, start_at: test_start_time, end_at: test_end_time)
        result_both = chunker_both.send(:determine_time_range)
        expect(result_both[0]).to be_within(1.second).of(test_start_time.to_time)
        expect(result_both[1]).to be_within(1.second).of(test_end_time.to_time)

        # Only start provided
        chunker_start = described_class.new(user, start_at: test_start_time)
        result_start = chunker_start.send(:determine_time_range)
        expect(result_start[0]).to be_within(1.second).of(test_start_time.to_time)
        expect(result_start[1]).to be_within(1.second).of(Time.current)

        # Only end provided
        chunker_end = described_class.new(user, end_at: test_end_time)
        result_end = chunker_end.send(:determine_time_range)
        expect(result_end[0]).to eq(Time.at(point1.timestamp))
        expect(result_end[1]).to be_within(1.second).of(test_end_time.to_time)

        # Neither provided
        chunker_neither = described_class.new(user)
        result_neither = chunker_neither.send(:determine_time_range)
        expect(result_neither[0]).to eq(Time.at(point1.timestamp))
        expect(result_neither[1]).to eq(Time.at(point2.timestamp))
      end

      context 'when user has no points and end_at is provided' do
        let(:user_no_points) { create(:user) }
        let(:chunker_no_points) { described_class.new(user_no_points, end_at: Time.current) }

        it 'returns nil' do
          expect(chunker_no_points.send(:determine_time_range)).to be_nil
        end
      end
    end
  end
end
