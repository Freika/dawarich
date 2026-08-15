# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260508193900_dedupe_tracks_for_unique_index')

RSpec.describe DedupeTracksForUniqueIndex do
  let(:start_at) { Time.zone.parse('2026-04-01 10:00:00') }
  let(:end_at) { Time.zone.parse('2026-04-01 10:30:00') }

  def without_changelog_consent_column
    connection = ActiveRecord::Base.connection
    connection.remove_column(:users, :changelog_consent)
    User.reset_column_information
    yield
  ensure
    connection.add_column(:users, :changelog_consent, :integer, if_not_exists: true)
    User.reset_column_information
  end

  def make_track(user)
    Track.create!(
      user_id: user.id,
      start_at: start_at,
      end_at: end_at,
      original_path: 'LINESTRING(13.4 52.5, 13.41 52.51)',
      distance: 100,
      duration: (end_at - start_at).to_i,
      avg_speed: 10
    )
  end

  it 'loads the User model when the changelog_consent column is absent' do
    without_changelog_consent_column do
      expect { User.new }.not_to raise_error
    end
  end

  it 'dedupes tracks when the changelog_consent column is absent' do
    user = create(:user)
    ActiveRecord::Base.connection.execute('DROP INDEX IF EXISTS index_tracks_on_user_start_end_unique')
    ActiveRecord::Base.connection.execute('DROP INDEX IF EXISTS index_tracks_on_user_tracker_start_end_unique')
    2.times { make_track(user) }

    without_changelog_consent_column do
      expect { described_class.new.up }.not_to raise_error
    end

    expect(user.tracks.count).to eq(1)
  end
end
