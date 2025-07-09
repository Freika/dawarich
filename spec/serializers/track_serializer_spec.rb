# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TrackSerializer do
  describe '#call' do
    let(:user) { create(:user) }

    context 'when serializing user tracks with track IDs' do
      subject(:serializer) { described_class.new(user, track_ids).call }

      let!(:track1) { create(:track, user: user, start_at: 2.hours.ago, end_at: 1.hour.ago) }
      let!(:track2) { create(:track, user: user, start_at: 4.hours.ago, end_at: 3.hours.ago) }
      let!(:track3) { create(:track, user: user, start_at: 6.hours.ago, end_at: 5.hours.ago) }
      let(:track_ids) { [track1.id, track2.id] }

      it 'returns an array of serialized tracks' do
        expect(serializer).to be_an(Array)
        expect(serializer.length).to eq(2)
      end

      it 'serializes each track correctly' do
        serialized_ids = serializer.map { |track| track[:id] }
        expect(serialized_ids).to contain_exactly(track1.id, track2.id)
        expect(serialized_ids).not_to include(track3.id)
      end

      it 'formats timestamps as ISO8601 for all tracks' do
        serializer.each do |track|
          expect(track[:start_at]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
          expect(track[:end_at]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
        end
      end

      it 'includes all required fields for each track' do
        serializer.each do |track|
          expect(track.keys).to contain_exactly(
            :id, :start_at, :end_at, :distance, :avg_speed, :duration,
            :elevation_gain, :elevation_loss, :elevation_max, :elevation_min, :original_path
          )
        end
      end

      it 'handles numeric values correctly' do
        serializer.each do |track|
          expect(track[:distance]).to be_a(Numeric)
          expect(track[:avg_speed]).to be_a(Numeric)
          expect(track[:duration]).to be_a(Numeric)
          expect(track[:elevation_gain]).to be_a(Numeric)
          expect(track[:elevation_loss]).to be_a(Numeric)
          expect(track[:elevation_max]).to be_a(Numeric)
          expect(track[:elevation_min]).to be_a(Numeric)
        end
      end

      it 'orders tracks by start_at in ascending order' do
        serialized_tracks = serializer
        expect(serialized_tracks.first[:id]).to eq(track2.id) # Started 4 hours ago
        expect(serialized_tracks.second[:id]).to eq(track1.id) # Started 2 hours ago
      end
    end

    context 'when track IDs belong to different users' do
      subject(:serializer) { described_class.new(user, track_ids).call }

      let(:other_user) { create(:user) }
      let!(:user_track) { create(:track, user: user) }
      let!(:other_user_track) { create(:track, user: other_user) }
      let(:track_ids) { [user_track.id, other_user_track.id] }

      it 'only returns tracks belonging to the specified user' do
        serialized_ids = serializer.map { |track| track[:id] }
        expect(serialized_ids).to contain_exactly(user_track.id)
        expect(serialized_ids).not_to include(other_user_track.id)
      end
    end

    context 'when track IDs array is empty' do
      subject(:serializer) { described_class.new(user, []).call }

      it 'returns an empty array' do
        expect(serializer).to eq([])
      end
    end

    context 'when track IDs contain non-existent IDs' do
      subject(:serializer) { described_class.new(user, track_ids).call }

      let!(:existing_track) { create(:track, user: user) }
      let(:track_ids) { [existing_track.id, 999999] }

      it 'only returns existing tracks' do
        serialized_ids = serializer.map { |track| track[:id] }
        expect(serialized_ids).to contain_exactly(existing_track.id)
        expect(serializer.length).to eq(1)
      end
    end
  end
end
