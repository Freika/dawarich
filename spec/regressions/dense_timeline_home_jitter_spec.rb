# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Dense Timeline history with position noise at home' do
  include ActiveSupport::Testing::TimeHelpers

  let(:start_at) { Time.utc(2026, 6, 1, 23, 30) }
  let(:latitude) { -40.0 }
  let(:meters_per_lon_degree) { 111_320 * Math.cos(latitude * Math::PI / 180) }

  let(:user) { create(:user, settings: { 'minutes_between_routes' => 30, 'meters_between_routes' => 500 }) }

  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
  end

  # Invented positions in the open South Pacific. Each day: a 30-minute journey,
  # then reports every 5 minutes at one place until the next day. Indoor fixes
  # scatter around that place by up to `noise_meters` east or west. Noise wider than
  # the default visit radius needs a user who raised it; a smaller visit radius never
  # makes stops stricter than the default.
  [30, 10].product([[30, 100], [80, 100], [80, 30], [150, 200]]).each do |route_minutes, (noise_meters, visit_radius)|
    it "keeps three daily journeys apart at #{route_minutes} min with ±#{noise_meters} m noise " \
       "and a #{visit_radius} m visit radius" do
      user.update!(settings: user.settings.merge('minutes_between_routes' => route_minutes,
                                                 'visit_radius_meters' => visit_radius))
      pattern = [0, 1, -1, 0.5, -0.5, 1, -1]
      rows = (0..582).map do |index|
        daily_step = [index % 288, 6].min
        base = -140.0 + (index / 288) * 0.012 + daily_step * 0.002
        at_home = daily_step == 6 && index % 288 > 6
        noise = at_home ? pattern[index % pattern.size] * noise_meters / meters_per_lon_degree : 0
        [index * 5, base + noise]
      end
      points = create_reports(rows)

      generate_and_resolve(points)

      durations = user.tracks.order(:start_at).pluck(:duration).map { |seconds| (seconds / 3600.0).round(1) }
      expect(user.tracks.count).to eq(3), "got #{user.tracks.count} track(s), hours: #{durations.inspect}"

      sql_segments = Track.get_segments_with_points(user.id, points.first.timestamp, points.last.timestamp,
                                                    route_minutes)
      expect(sql_segments.size).to eq(3), "SQL segmentation found #{sql_segments.size} segment(s)"
    end
  end

  def create_reports(rows)
    payloads = rows.map do |minute, longitude|
      { timestamp: (start_at + minute.minutes).to_i, lonlat: "POINT(#{longitude} #{latitude})",
        tracker_id: 'google-maps-phone-timeline-export' }
    end
    Points::Intake.call(user_id: user.id, mode: :bulk, payloads: payloads)
    user.points.order(:timestamp).to_a
  end

  def generate_and_resolve(points)
    session = instance_double(Tracks::SessionManager, session_exists?: true,
                                                     increment_completed_chunks: true,
                                                     increment_tracks_created: true)
    allow(Tracks::SessionManager).to receive(:new).with(user.id, 'synthetic-timeline').and_return(session)
    chunk = {
      chunk_id: 'synthetic-timeline-chunk',
      start_timestamp: points.first.timestamp, end_timestamp: points.last.timestamp,
      buffer_start_timestamp: points.first.timestamp, buffer_end_timestamp: points.last.timestamp
    }

    travel_to(start_at + 4.days) do
      Tracks::TimeChunkProcessorJob.perform_now(user.id, 'synthetic-timeline', chunk)
      Tracks::BoundaryDetector.new(user).resolve_cross_chunk_tracks
    end
  end
end
