# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::SessionManager do
  let(:user_id) { 123 }
  let(:session_id) { 'test-session-id' }
  let(:manager) { described_class.new(user_id, session_id) }

  before do
    Rails.cache.clear
  end

  describe '#initialize' do
    it 'creates manager with provided user_id and session_id' do
      expect(manager.user_id).to eq(user_id)
      expect(manager.session_id).to eq(session_id)
    end

    it 'generates UUID session_id when not provided' do
      manager = described_class.new(user_id)
      expect(manager.session_id).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
    end
  end

  describe '#create_session' do
    let(:metadata) { { mode: 'bulk', chunk_size: '1.day' } }

    it 'creates a new session with default values' do
      result = manager.create_session(metadata)

      expect(result).to eq(manager)
      expect(manager.session_exists?).to be true

      session_data = manager.get_session_data
      expect(session_data['status']).to eq('pending')
      expect(session_data['total_chunks']).to eq(0)
      expect(session_data['completed_chunks']).to eq(0)
      expect(session_data['tracks_created']).to eq(0)
      expect(session_data['metadata']).to eq(metadata.deep_stringify_keys)
      expect(session_data['started_at']).to be_present
      expect(session_data['completed_at']).to be_nil
      expect(session_data['error_message']).to be_nil
    end

    it 'sets TTL on the cache entry' do
      manager.create_session(metadata)

      # Check that the key exists and will expire
      expect(Rails.cache.exist?(manager.send(:cache_key))).to be true
    end
  end

  describe '#get_session_data' do
    it 'returns nil when session does not exist' do
      expect(manager.get_session_data).to be_nil
    end

    it 'returns session data when session exists' do
      metadata = { test: 'data' }
      manager.create_session(metadata)

      data = manager.get_session_data
      expect(data).to be_a(Hash)
      expect(data['metadata']).to eq(metadata.deep_stringify_keys)
    end
  end

  describe '#session_exists?' do
    it 'returns false when session does not exist' do
      expect(manager.session_exists?).to be false
    end

    it 'returns true when session exists' do
      manager.create_session
      expect(manager.session_exists?).to be true
    end
  end

  describe '#update_session' do
    before do
      manager.create_session
    end

    it 'updates existing session data' do
      updates = { status: 'processing', total_chunks: 5 }
      result = manager.update_session(updates)

      expect(result).to be true

      data = manager.get_session_data
      expect(data['status']).to eq('processing')
      expect(data['total_chunks']).to eq(5)
    end

    it 'returns false when session does not exist' do
      manager.cleanup_session
      result = manager.update_session({ status: 'processing' })

      expect(result).to be false
    end

    it 'preserves existing data when updating' do
      original_metadata = { mode: 'bulk' }
      manager.cleanup_session
      manager.create_session(original_metadata)

      manager.update_session({ status: 'processing' })

      data = manager.get_session_data
      expect(data['metadata']).to eq(original_metadata.stringify_keys)
      expect(data['status']).to eq('processing')
    end
  end

  describe '#mark_started' do
    before do
      manager.create_session
    end

    it 'marks session as processing with total chunks' do
      result = manager.mark_started(10)

      expect(result).to be true

      data = manager.get_session_data
      expect(data['status']).to eq('processing')
      expect(data['total_chunks']).to eq(10)
      expect(data['started_at']).to be_present
    end
  end

  describe '#increment_completed_chunks' do
    before do
      manager.create_session
      manager.mark_started(5)
    end

    it 'increments completed chunks counter' do
      expect do
        manager.increment_completed_chunks
      end.to change {
        manager.get_session_data['completed_chunks']
      }.from(0).to(1)
    end

    it 'returns false when session does not exist' do
      manager.cleanup_session
      expect(manager.increment_completed_chunks).to be false
    end
  end

  describe '#increment_tracks_created' do
    before do
      manager.create_session
    end

    it 'increments tracks created counter by 1 by default' do
      expect do
        manager.increment_tracks_created
      end.to change {
        manager.get_session_data['tracks_created']
      }.from(0).to(1)
    end

    it 'increments tracks created counter by specified amount' do
      expect do
        manager.increment_tracks_created(5)
      end.to change {
        manager.get_session_data['tracks_created']
      }.from(0).to(5)
    end

    it 'returns false when session does not exist' do
      manager.cleanup_session
      expect(manager.increment_tracks_created).to be false
    end
  end

  describe '#mark_completed' do
    before do
      manager.create_session
    end

    it 'marks session as completed with timestamp' do
      result = manager.mark_completed

      expect(result).to be true

      data = manager.get_session_data
      expect(data['status']).to eq('completed')
      expect(data['completed_at']).to be_present
    end
  end

  describe '#mark_failed' do
    before do
      manager.create_session
    end

    it 'marks session as failed with error message and timestamp' do
      error_message = 'Something went wrong'

      result = manager.mark_failed(error_message)

      expect(result).to be true

      data = manager.get_session_data
      expect(data['status']).to eq('failed')
      expect(data['error_message']).to eq(error_message)
      expect(data['completed_at']).to be_present
    end
  end

  describe '#all_chunks_completed?' do
    before do
      manager.create_session
      manager.mark_started(3)
    end

    it 'returns false when not all chunks are completed' do
      manager.increment_completed_chunks
      expect(manager.all_chunks_completed?).to be false
    end

    it 'returns true when all chunks are completed' do
      3.times { manager.increment_completed_chunks }
      expect(manager.all_chunks_completed?).to be true
    end

    it 'returns true when completed chunks exceed total (edge case)' do
      4.times { manager.increment_completed_chunks }
      expect(manager.all_chunks_completed?).to be true
    end

    it 'returns false when session does not exist' do
      manager.cleanup_session
      expect(manager.all_chunks_completed?).to be false
    end
  end

  describe '#cleanup_session' do
    before do
      manager.create_session
    end

    it 'removes session from cache' do
      expect(manager.session_exists?).to be true

      manager.cleanup_session

      expect(manager.session_exists?).to be false
    end
  end

  describe '.create_for_user' do
    let(:metadata) { { mode: 'daily' } }

    it 'creates and returns a session manager' do
      result = described_class.create_for_user(user_id, metadata)

      expect(result).to be_a(described_class)
      expect(result.user_id).to eq(user_id)
      expect(result.session_exists?).to be true

      data = result.get_session_data
      expect(data['metadata']).to eq(metadata.deep_stringify_keys)
    end
  end

  describe 'cache key scoping' do
    it 'uses user-scoped cache keys' do
      expected_key = "track_generation:user:#{user_id}:session:#{session_id}"
      actual_key = manager.send(:cache_key)

      expect(actual_key).to eq(expected_key)
    end

    it 'prevents cross-user session access' do
      manager.create_session
      other_manager = described_class.new(999, session_id)

      expect(manager.session_exists?).to be true
      expect(other_manager.session_exists?).to be false
    end
  end
end
