# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::ParallelGenerator do
  let(:user) { create(:user) }
  let(:generator) { described_class.new(user, **options) }
  let(:options) { {} }

  before do
    Rails.cache.clear
    # Stub user settings
    allow(user.safe_settings).to receive(:minutes_between_routes).and_return(30)
    allow(user.safe_settings).to receive(:meters_between_routes).and_return(500)
  end

  describe '#initialize' do
    it 'sets default values' do
      expect(generator.user).to eq(user)
      expect(generator.start_at).to be_nil
      expect(generator.end_at).to be_nil
      expect(generator.mode).to eq(:bulk)
      expect(generator.chunk_size).to eq(1.day)
    end

    it 'accepts custom options' do
      start_time = 1.week.ago
      end_time = Time.current

      custom_generator = described_class.new(
        user,
        start_at: start_time,
        end_at: end_time,
        mode: :daily,
        chunk_size: 2.days
      )

      expect(custom_generator.start_at).to eq(start_time)
      expect(custom_generator.end_at).to eq(end_time)
      expect(custom_generator.mode).to eq(:daily)
      expect(custom_generator.chunk_size).to eq(2.days)
    end

    it 'converts mode to symbol' do
      generator = described_class.new(user, mode: 'incremental')
      expect(generator.mode).to eq(:incremental)
    end
  end

  describe '#call' do
    let!(:point1) { create(:point, user: user, timestamp: 2.days.ago.to_i) }
    let!(:point2) { create(:point, user: user, timestamp: 1.day.ago.to_i) }

    context 'with successful execution' do
      it 'returns a session manager' do
        result = generator.call

        expect(result).to be_a(Tracks::SessionManager)
        expect(result.user_id).to eq(user.id)
        expect(result.session_exists?).to be true
      end

      it 'creates session with correct metadata' do
        result = generator.call

        session_data = result.get_session_data
        expect(session_data['metadata']['mode']).to eq('bulk')
        expect(session_data['metadata']['chunk_size']).to eq('1 day')
        expect(session_data['metadata']['user_settings']['time_threshold_minutes']).to eq(30)
        expect(session_data['metadata']['user_settings']['distance_threshold_meters']).to eq(500)
      end

      it 'marks session as started with chunk count' do
        result = generator.call

        session_data = result.get_session_data
        expect(session_data['status']).to eq('processing')
        expect(session_data['total_chunks']).to be > 0
        expect(session_data['started_at']).to be_present
      end

      it 'enqueues time chunk processor jobs' do
        expect { generator.call }.to \
          have_enqueued_job(Tracks::TimeChunkProcessorJob).at_least(:once)
      end

      it 'enqueues boundary resolver job with delay' do
        expect { generator.call }.to \
          have_enqueued_job(Tracks::BoundaryResolverJob).at(be >= 5.minutes.from_now)
      end

      it 'logs the operation' do
        allow(Rails.logger).to receive(:info) # Allow any log messages
        expect(Rails.logger).to receive(:info).with(/Started parallel track generation/).at_least(:once)
        generator.call
      end
    end

    context 'when no time chunks are generated' do
      let(:user_no_points) { create(:user) }
      let(:generator) { described_class.new(user_no_points) }

      it 'returns 0 (no session created)' do
        result = generator.call
        expect(result).to eq(0)
      end

      it 'does not enqueue any jobs' do
        expect { generator.call }.not_to have_enqueued_job
      end
    end

    context 'with different modes' do
      let!(:track1) { create(:track, user: user, start_at: 2.days.ago) }
      let!(:track2) { create(:track, user: user, start_at: 1.day.ago) }

      context 'bulk mode' do
        let(:options) { { mode: :bulk } }

        it 'cleans existing tracks' do
          expect(user.tracks.count).to eq(2)

          generator.call

          expect(user.tracks.count).to eq(0)
        end
      end

      context 'daily mode' do
        let(:options) { { mode: :daily, start_at: 1.day.ago.beginning_of_day } }

        it 'cleans tracks for the specific day' do
          expect(user.tracks.count).to eq(2)

          generator.call

          # Should only clean tracks from the specified day
          remaining_tracks = user.tracks.count
          expect(remaining_tracks).to be < 2
        end
      end

      context 'incremental mode' do
        let(:options) { { mode: :incremental } }

        it 'does not clean existing tracks' do
          expect(user.tracks.count).to eq(2)

          generator.call

          expect(user.tracks.count).to eq(2)
        end
      end
    end

    context 'with time range specified' do
      let(:start_time) { 3.days.ago }
      let(:end_time) { 1.day.ago }
      let(:options) { { start_at: start_time, end_at: end_time, mode: :bulk } }
      let!(:track_in_range) { create(:track, user: user, start_at: 2.days.ago) }
      let!(:track_out_of_range) { create(:track, user: user, start_at: 1.week.ago) }

      it 'only cleans tracks within the specified range' do
        expect(user.tracks.count).to eq(2)

        generator.call

        # Should only clean the track within the time range
        remaining_tracks = user.tracks
        expect(remaining_tracks.count).to eq(1)
        expect(remaining_tracks.first).to eq(track_out_of_range)
      end

      it 'includes time range in session metadata' do
        result = generator.call

        session_data = result.get_session_data
        expect(session_data['metadata']['start_at']).to eq(start_time.iso8601)
        expect(session_data['metadata']['end_at']).to eq(end_time.iso8601)
      end
    end

    context 'job coordination' do
      it 'calculates estimated delay based on chunk count' do
        # Create more points to generate more chunks
        10.times do |i|
          create(:point, user: user, timestamp: (10 - i).days.ago.to_i)
        end

        expect do
          generator.call
        end.to have_enqueued_job(Tracks::BoundaryResolverJob)
          .with(user.id, kind_of(String))
      end

      it 'ensures minimum delay for boundary resolver' do
        # Even with few chunks, should have minimum delay
        expect do
          generator.call
        end.to have_enqueued_job(Tracks::BoundaryResolverJob)
          .at(be >= 5.minutes.from_now)
      end
    end

    context 'error handling in private methods' do
      it 'handles unknown mode in should_clean_tracks?' do
        generator.instance_variable_set(:@mode, :unknown)

        expect(generator.send(:should_clean_tracks?)).to be false
      end

      it 'raises error for unknown mode in clean_existing_tracks' do
        generator.instance_variable_set(:@mode, :unknown)

        expect do
          generator.send(:clean_existing_tracks)
        end.to raise_error(ArgumentError, 'Unknown mode: unknown')
      end
    end

    context 'user settings integration' do
      let(:mock_settings) { double('SafeSettings') }

      before do
        # Create a proper mock and stub user.safe_settings to return it
        allow(mock_settings).to receive(:minutes_between_routes).and_return(60)
        allow(mock_settings).to receive(:meters_between_routes).and_return(1000)
        allow(user).to receive(:safe_settings).and_return(mock_settings)
      end

      it 'includes user settings in session metadata' do
        result = generator.call

        session_data = result.get_session_data
        user_settings = session_data['metadata']['user_settings']
        expect(user_settings['time_threshold_minutes']).to eq(60)
        expect(user_settings['distance_threshold_meters']).to eq(1000)
      end

      it 'caches user settings' do
        # Call the methods multiple times
        generator.send(:time_threshold_minutes)
        generator.send(:time_threshold_minutes)
        generator.send(:distance_threshold_meters)
        generator.send(:distance_threshold_meters)

        # Should only call safe_settings once per method due to memoization
        expect(mock_settings).to have_received(:minutes_between_routes).once
        expect(mock_settings).to have_received(:meters_between_routes).once
      end
    end
  end

  describe 'private methods' do
    describe '#generate_time_chunks' do
      let!(:point1) { create(:point, user: user, timestamp: 2.days.ago.to_i) }
      let!(:point2) { create(:point, user: user, timestamp: 1.day.ago.to_i) }

      it 'creates TimeChunker with correct parameters' do
        expect(Tracks::TimeChunker).to receive(:new)
          .with(user, start_at: nil, end_at: nil, chunk_size: 1.day)
          .and_call_original

        generator.send(:generate_time_chunks)
      end

      it 'returns chunks from TimeChunker' do
        chunks = generator.send(:generate_time_chunks)
        expect(chunks).to be_an(Array)
        expect(chunks).not_to be_empty
      end
    end

    describe '#enqueue_chunk_jobs' do
      let(:session_id) { 'test-session' }
      let(:chunks) { [
        { chunk_id: 'chunk1', start_timestamp: 1.day.ago.to_i },
        { chunk_id: 'chunk2', start_timestamp: 2.days.ago.to_i }
      ] }

      it 'enqueues job for each chunk' do
        expect {
          generator.send(:enqueue_chunk_jobs, session_id, chunks)
        }.to have_enqueued_job(Tracks::TimeChunkProcessorJob)
          .exactly(2).times
      end

      it 'passes correct parameters to each job' do
        expect(Tracks::TimeChunkProcessorJob).to receive(:perform_later)
          .with(user.id, session_id, chunks[0])
        expect(Tracks::TimeChunkProcessorJob).to receive(:perform_later)
          .with(user.id, session_id, chunks[1])

        generator.send(:enqueue_chunk_jobs, session_id, chunks)
      end
    end

    describe '#enqueue_boundary_resolver' do
      let(:session_id) { 'test-session' }

      it 'enqueues boundary resolver with estimated delay' do
        expect {
          generator.send(:enqueue_boundary_resolver, session_id, 5)
        }.to have_enqueued_job(Tracks::BoundaryResolverJob)
          .with(user.id, session_id)
          .at(be >= 2.minutes.from_now)
      end

      it 'uses minimum delay for small chunk counts' do
        expect do
          generator.send(:enqueue_boundary_resolver, session_id, 1)
        end.to have_enqueued_job(Tracks::BoundaryResolverJob)
          .at(be >= 5.minutes.from_now)
      end

      it 'scales delay with chunk count' do
        expect do
          generator.send(:enqueue_boundary_resolver, session_id, 20)
        end.to have_enqueued_job(Tracks::BoundaryResolverJob)
          .at(be >= 10.minutes.from_now)
      end
    end

    describe 'time range handling' do
      let(:start_time) { 3.days.ago }
      let(:end_time) { 1.day.ago }
      let(:generator) { described_class.new(user, start_at: start_time, end_at: end_time) }

      describe '#time_range_defined?' do
        it 'returns true when start_at or end_at is defined' do
          expect(generator.send(:time_range_defined?)).to be true
        end

        it 'returns false when neither is defined' do
          generator = described_class.new(user)
          expect(generator.send(:time_range_defined?)).to be false
        end
      end

      describe '#time_range' do
        it 'creates proper time range when both defined' do
          range = generator.send(:time_range)
          expect(range.begin).to eq(Time.zone.at(start_time.to_i))
          expect(range.end).to eq(Time.zone.at(end_time.to_i))
        end

        it 'creates open-ended range when only start defined' do
          generator = described_class.new(user, start_at: start_time)
          range = generator.send(:time_range)
          expect(range.begin).to eq(Time.zone.at(start_time.to_i))
          expect(range.end).to be_nil
        end

        it 'creates range with open beginning when only end defined' do
          generator = described_class.new(user, end_at: end_time)
          range = generator.send(:time_range)
          expect(range.begin).to be_nil
          expect(range.end).to eq(Time.zone.at(end_time.to_i))
        end
      end

      describe '#daily_time_range' do
        let(:day) { 2.days.ago.to_date }
        let(:generator) { described_class.new(user, start_at: day) }

        it 'creates range for entire day' do
          range = generator.send(:daily_time_range)
          expect(range.begin).to eq(day.beginning_of_day.to_i)
          expect(range.end).to eq(day.end_of_day.to_i)
        end

        it 'uses current date when start_at not provided' do
          generator = described_class.new(user)
          range = generator.send(:daily_time_range)
          expect(range.begin).to eq(Date.current.beginning_of_day.to_i)
          expect(range.end).to eq(Date.current.end_of_day.to_i)
        end
      end
    end
  end
end
