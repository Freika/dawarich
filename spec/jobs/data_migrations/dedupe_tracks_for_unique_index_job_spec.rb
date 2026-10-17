# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::DedupeTracksForUniqueIndexJob, type: :job do
  before do
    ActiveRecord::Base.connection.execute(
      'DROP INDEX IF EXISTS index_tracks_on_user_start_end_unique'
    )
    ActiveRecord::Base.connection.execute(
      'DROP INDEX IF EXISTS index_tracks_on_user_tracker_start_end_unique'
    )
  end

  let(:start_time) { 2.hours.ago }
  let(:end_time) { 1.hour.ago }

  describe '#perform' do
    context 'when an active user has duplicate tracks' do
      let(:user) { create(:user) }
      let!(:older_track) { create(:track, user: user, start_at: start_time, end_at: end_time) }
      let!(:newer_track) { create(:track, user: user, start_at: start_time, end_at: end_time) }

      it 'removes the duplicate, keeping the track Tracks::Deduplicator would keep' do
        described_class.perform_now

        expect(Track.exists?(older_track.id)).to be false
        expect(Track.exists?(newer_track.id)).to be true
      end
    end

    context 'when a soft-deleted user has duplicate tracks' do
      let(:user) { create(:user) }
      let!(:older_track) { create(:track, user: user, start_at: start_time, end_at: end_time) }
      let!(:newer_track) { create(:track, user: user, start_at: start_time, end_at: end_time) }

      before { user.mark_as_deleted! }

      it 'still removes the duplicate' do
        described_class.perform_now

        expect(Track.exists?(older_track.id)).to be false
        expect(Track.exists?(newer_track.id)).to be true
      end
    end

    context 'when users have no duplicate tracks' do
      let(:user) { create(:user) }
      let!(:track) { create(:track, user: user, start_at: start_time, end_at: end_time) }

      it 'leaves their tracks untouched' do
        described_class.perform_now

        expect(Track.exists?(track.id)).to be true
      end
    end
  end
end
