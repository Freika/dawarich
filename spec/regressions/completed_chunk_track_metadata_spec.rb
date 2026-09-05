# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Completed chunk track metadata' do
  let(:user) { create(:user, settings: { 'minutes_between_routes' => 60, 'meters_between_routes' => 100 }) }
  let(:base_time) { Time.utc(2026, 7, 17) }

  def generate_chunks(order, tracker_id: 'synthetic-device', step: 0.1)
    rows = 217.times.map do |index|
      { user_id: user.id, timestamp: base_time.to_i + index * 1200,
        lonlat: "POINT(#{13 + index * step} 52)", tracker_id: tracker_id,
        altitude: index, anomaly: false, created_at: Time.current, updated_at: Time.current }
    end
    Point.insert_all!(rows)
    chunks = Tracks::TimeChunker.new(user, start_at: base_time, end_at: base_time + 3.days).call
    session = Tracks::SessionManager.create_for_user(user.id)
    session.mark_started(chunks.size)
    order.each do |index|
      Tracks::TimeChunkProcessorJob.perform_now(user.id, session.session_id, chunks.fetch(index))
    end
    Tracks::BoundaryResolverJob.perform_now(user.id, session.session_id)
    expect(session.get_session_data.fetch('status')).to eq('completed')
    session.get_session_data
  ensure
    session&.cleanup_session
  end

  def expect_consistent_metadata
    expect(user.points.where.not(track_id: nil).count).to eq(217)
    user.tracks.each do |track|
      points = track.points.order(:timestamp).to_a
      expect(track.start_at.to_i).to eq(points.first.timestamp)
      expect(track.end_at.to_i).to eq(points.last.timestamp)
      expect(track.duration).to eq(points.last.timestamp - points.first.timestamp)
      # Initial generation uses a sphere; model recalculation uses the PostGIS
      # spheroid. Both must describe these members, within that earth-model gap.
      distance = Point.calculate_distance_for_array_geocoder(points, :m)
      expect(track.distance).to be_within(distance * 0.005).of(distance)
      expect(track.avg_speed.to_f).to eq(Track.avg_speed_kmh(track.distance, track.duration))
      expect(track.elevation_gain).to eq(points.last.altitude - points.first.altitude)
      expect(track.elevation_min).to eq(points.first.altitude)
      expect(track.elevation_max).to eq(points.last.altitude)
      expect(track.track_segments.auto_classified.minimum(:start_at)).to be >= track.start_at
      expect(track.track_segments.auto_classified.maximum(:end_at)).to be <= track.end_at
    end
  end

  [[0, 1, 2], [2, 1, 0], [0, 2, 1]].each do |order|
    it "refreshes surviving partial tracks after chunks finish in order #{order}" do
      generate_chunks(order)
      expect(user.tracks.count).to eq(3)
      expect_consistent_metadata
    end
  end

  it 'refreshes imported points without a device identifier' do
    generate_chunks([0, 1, 2], tracker_id: nil, step: 0.01)
    expect(user.tracks.count).to eq(3)
    expect_consistent_metadata
  end

  it 'retains the existing merge for a densely sampled route' do
    generate_chunks([0, 2, 1], step: 0.01)
    expect(user.tracks.count).to eq(1)
    expect_consistent_metadata
  end

  it 'reports an unsupported historical track and still completes the new tracks' do
    historical = create(:track, user: user, start_at: base_time - 3.days,
                               end_at: base_time - 2.days, created_at: 3.days.ago)
    create(:point, user: user, track: historical, timestamp: (base_time - 3.days).to_i)
    original = historical.attributes

    data = generate_chunks([0, 1, 2])

    expect(data.dig('metadata', 'track_metadata_refresh')).to include(
      'refreshed' => 2, 'skipped' => 1, 'reasons' => { 'insufficient_points' => 1 }, 'sample_ids' => [historical.id]
    )
    expect(historical.reload.attributes).to eq(original)
    expect(user.tracks.where.not(id: historical.id).count).to eq(3)
    user.tracks.where.not(id: historical.id).find_each do |track|
      bounds = track.points.pick(Arel.sql('MIN(timestamp), MAX(timestamp)'))
      expect([track.start_at.to_i, track.end_at.to_i]).to eq(bounds)
    end
  end
end
