# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::TransportationRecalculationStatus do
  let(:user) { create(:user) }
  let(:status) { described_class.new(user.id) }

  describe '#in_progress?' do
    it 'returns false when no recalculation is running' do
      expect(status.in_progress?).to be false
    end

    it 'returns true when recalculation is processing' do
      status.start(total_tracks: 10)
      expect(status.in_progress?).to be true
    end

    it 'returns false when recalculation is completed' do
      status.start(total_tracks: 10)
      status.complete
      expect(status.in_progress?).to be false
    end
  end

  describe '#current_status' do
    it 'returns idle when nothing is cached' do
      expect(status.current_status).to eq('idle')
    end

    it 'returns processing after start' do
      status.start(total_tracks: 10)
      expect(status.current_status).to eq('processing')
    end

    it 'returns completed after complete' do
      status.start(total_tracks: 10)
      status.complete
      expect(status.current_status).to eq('completed')
    end

    it 'returns failed after fail' do
      status.start(total_tracks: 10)
      status.fail('Something went wrong')
      expect(status.current_status).to eq('failed')
    end
  end

  describe '#data' do
    it 'returns idle status hash when nothing is cached' do
      expect(status.data).to eq({ 'status' => 'idle' })
    end

    it 'returns full data after start' do
      status.start(total_tracks: 10)
      data = status.data

      expect(data['status']).to eq('processing')
      expect(data['total_tracks']).to eq(10)
      expect(data['processed_tracks']).to eq(0)
      expect(data['started_at']).to be_present
    end
  end

  describe '#start' do
    it 'sets processing status with track count' do
      status.start(total_tracks: 25)
      data = status.data

      expect(data['status']).to eq('processing')
      expect(data['total_tracks']).to eq(25)
      expect(data['processed_tracks']).to eq(0)
    end
  end

  describe '#update_progress' do
    it 'updates the processed tracks count' do
      status.start(total_tracks: 100)
      status.update_progress(processed_tracks: 50, total_tracks: 100)

      expect(status.data['processed_tracks']).to eq(50)
    end
  end

  describe '#complete' do
    it 'sets completed status with timestamp' do
      status.start(total_tracks: 10)
      status.complete
      data = status.data

      expect(data['status']).to eq('completed')
      expect(data['completed_at']).to be_present
    end
  end

  describe '#fail' do
    it 'sets failed status with error message' do
      status.start(total_tracks: 10)
      status.fail('Database connection lost')
      data = status.data

      expect(data['status']).to eq('failed')
      expect(data['error_message']).to eq('Database connection lost')
      expect(data['completed_at']).to be_present
    end
  end

  describe '#cache_key' do
    it 'returns the correct cache key format' do
      expect(status.cache_key).to eq("transportation_mode_recalculation:user:#{user.id}")
    end
  end
end
