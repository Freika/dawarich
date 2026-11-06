# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261102000200_ensure_points_altitude_decimal.rb')

# Since 1.17.0 Tracks::TrackBuilder selects points.altitude_decimal, so
# instances that never got the column built no new tracks (#3915). Adding the
# column queues a catch-up that builds the missed tracks.
RSpec.describe 'Tracks after the points schema repair' do
  include ActiveJob::TestHelper

  let(:connection) { ApplicationRecord.connection }
  let(:user) { create(:user) }

  before do
    create(:track, user: user, start_at: 2.days.ago, end_at: 2.days.ago + 1.hour)
    12.times do |i|
      create(:point, user: user, timestamp: 1.hour.ago.to_i + (i * 60),
                     lonlat: "POINT(#{13.40 + (i * 0.002)} 52.52)")
    end
    user.update!(points_count: user.points.count)
    allow(User).to receive(:active_or_trial).and_return(User.where(id: user.id))

    connection.execute('ALTER TABLE points DROP COLUMN altitude_decimal')
    Point.reset_column_information
    Points::DimensionResolver.reset_column_availability!
  end

  after do
    connection.execute('ALTER TABLE points ADD COLUMN IF NOT EXISTS altitude_decimal numeric(10,2)')
    Point.reset_column_information
    Points::DimensionResolver.reset_column_availability!
  end

  def new_tracks
    user.tracks.where('start_at > ?', 1.day.ago)
  end

  it 'builds no tracks while the column is missing' do
    perform_enqueued_jobs { Tracks::DailyGenerationJob.perform_now }

    expect(new_tracks).to be_empty
  end

  it 'builds the missed tracks once the migration adds the column' do
    perform_enqueued_jobs { EnsurePointsAltitudeDecimal.new.up }

    expect(new_tracks).to exist
  end
end
