# frozen_string_literal: true

require 'rails_helper'
require 'tempfile'

RSpec.describe 'Imported GPX splits the surrounding low accuracy track' do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, settings: { 'minutes_between_routes' => 60, 'timezone' => 'UTC' }) }
  let(:started_at) { Time.utc(2026, 6, 1, 8) }

  # Synthetic ocean coordinates. These are the points left after deleting the
  # low accuracy fixes recorded during the watch journey.
  let!(:surrounding) do
    [[0, -140.002], [60, -140.0], [1200, -139.95], [1260, -139.948]].map do |seconds, lon|
      create(:point, user: user, tracker_id: 'owntracks-phone',
                     timestamp: started_at.to_i + seconds, lonlat: "POINT(#{lon} -40.0)")
    end
  end

  def import_watch_gpx(samples)
    import = create(:import, user: user, name: 'synthetic-watch.gpx', source: 'gpx')
    trackpoints = samples.map do |seconds, lon, lat|
      "<trkpt lat=\"#{lat}\" lon=\"#{lon}\"><time>#{(started_at + seconds).iso8601}</time></trkpt>"
    end.join

    FileUtils.mkdir_p(Rails.root.join('tmp/factory'))
    Tempfile.create(['synthetic-watch', '.gpx'], Rails.root.join('tmp/factory')) do |file|
      file.write("<gpx version=\"1.1\"><trk><trkseg>#{trackpoints}</trkseg></trk></gpx>")
      file.flush
      Gpx::TrackImporter.new(import, user.id, file.path).call
    end
    import.points.order(:timestamp).to_a
  end

  def generate_tracks(untracked_only: false)
    session = nil
    perform_enqueued_jobs(only: [Tracks::TimeChunkProcessorJob, Tracks::BoundaryResolverJob]) do
      session = Tracks::ParallelGenerator.new(
        user, start_at: started_at.beginning_of_day, end_at: started_at.end_of_day, untracked_only:
      ).call
    end
  ensure
    session&.cleanup_session
  end

  def track_sections
    user.tracks.reload.order(:start_at).map { |track| track.points.order(:timestamp).pluck(:id) }
  end

  def day_distance_km
    Timeline::DayAssembler.new(
      user, start_at: started_at.beginning_of_day.iso8601, end_at: started_at.end_of_day.iso8601
    ).call.first.dig(:summary, :total_distance)
  end

  def expect_split_around(imported)
    expected_sections = [surrounding.first(2), imported, surrounding.last(2)]
    expect(track_sections).to eq(expected_sections.map { |section| section.map(&:id) })

    expected_distance_m = expected_sections.sum do |section|
      Point.calculate_distance_for_array_geocoder(section, :m).round
    end
    expect(day_distance_km).to eq((expected_distance_m / 1000.0).round(1))
  end

  let(:watch_samples) { [[120, -140.0, -40.0], [660, -139.975, -39.99], [1140, -139.95, -40.0]] }

  it 'keeps the surrounding sections separate on a full generation', :aggregate_failures do
    imported = import_watch_gpx(watch_samples)

    generate_tracks

    expect_split_around(imported)
  end

  it 'splits the already generated phone track when the GPX is imported later', :aggregate_failures do
    generate_tracks
    expect(track_sections).to eq([surrounding.map(&:id)])
    user.tracks.update_all(created_at: 2.days.ago)

    imported = import_watch_gpx(watch_samples)
    generate_tracks(untracked_only: true)

    expect_split_around(imported)
  end

  it 'keeps the phone track and its shared link as the first section', :aggregate_failures do
    generate_tracks
    phone_track = user.tracks.sole
    link = create(:shared_link, user: user, resource_type: :track, resource_id: phone_track.id)

    import_watch_gpx(watch_samples)
    generate_tracks(untracked_only: true)

    expect(user.tracks.order(:start_at).first.id).to eq(phone_track.id)
    expect(SharedLink.exists?(link.id)).to be(true)
  end

  it 'splits tracks created more than an hour ago when the generation started earlier', :aggregate_failures do
    imported = import_watch_gpx(watch_samples)
    perform_enqueued_jobs(only: Tracks::TimeChunkProcessorJob) do
      Tracks::ParallelGenerator.new(user, start_at: started_at.beginning_of_day, end_at: started_at.end_of_day).call
    end
    user.tracks.update_all(created_at: 2.hours.ago)
    session = travel_to(3.hours.ago) { Tracks::SessionManager.new(user.id).create_session }

    Tracks::BoundaryResolverJob.perform_now(user.id, session.session_id)

    expect_split_around(imported)
  ensure
    session&.cleanup_session
  end

  it 'leaves the phone track whole when the watch recorded alongside it', :aggregate_failures do
    concurrent = [[30, -140.001, -40.0], [660, -139.975, -39.99], [1230, -139.949, -40.0]]
    imported = import_watch_gpx(concurrent)

    generate_tracks

    expect(track_sections).to eq([surrounding.map(&:id), imported.map(&:id)])
  end
end

RSpec.describe 'Realtime tracks do not merge across another tracker handoff' do
  let(:user) { create(:user, settings: { 'minutes_between_routes' => 60, 'timezone' => 'UTC' }) }

  def record(tracker_id, minutes_ago, lon)
    create(:point, user: user, tracker_id: tracker_id,
                   timestamp: minutes_ago.minutes.ago.to_i, lonlat: "POINT(#{lon} -40.0)")
  end

  it 'keeps the phone tracks apart around the watch track' do
    record('owntracks-phone', 60, -140.002)
    record('owntracks-phone', 59, -140.0)
    [[55, -140.0], [50, -139.975], [45, -139.95]].each { |minutes, lon| record('watch', minutes, lon) }
    Tracks::IncrementalGenerator.new(user).call

    record('owntracks-phone', 40, -139.95)
    record('owntracks-phone', 39, -139.948)
    Tracks::IncrementalGenerator.new(user).call

    expect(user.tracks.where(tracker_id: 'owntracks-phone').count).to eq(2)
  end

  it 'leaves single phone points without a track when nothing remains to connect' do
    record('owntracks-phone', 60, -140.002)
    [[55, -140.0], [50, -139.975], [45, -139.95]].each { |minutes, lon| record('watch', minutes, lon) }
    record('owntracks-phone', 40, -139.948)
    Tracks::IncrementalGenerator.new(user).call

    expect(user.tracks.where(tracker_id: 'owntracks-phone')).to be_empty
    expect(user.points.where(tracker_id: 'owntracks-phone').pluck(:track_id)).to all(be_nil)
  end

  it 'treats a blank tracker id and a missing one as the same tracker' do
    [[60, -140.002], [59, -140.0], [44, -139.95], [43, -139.948]].each { |minutes, lon| record('', minutes, lon) }
    [[55, -140.0], [50, -139.975]].each { |minutes, lon| record(nil, minutes, lon) }
    Tracks::IncrementalGenerator.new(user).call

    expect(user.tracks.where(tracker_id: '').count).to eq(1)
  end

  it 'splits a phone batch uploaded after the watch track' do
    [[55, -140.0], [50, -139.975], [45, -139.95]].each { |minutes, lon| record('watch', minutes, lon) }
    Tracks::IncrementalGenerator.new(user).call
    user.tracks.update_all(created_at: 2.hours.ago)

    [[60, -140.002], [59, -140.0], [40, -139.95], [39, -139.948]].each do |minutes, lon|
      record('owntracks-phone', minutes, lon)
    end
    Tracks::IncrementalGenerator.new(user).call

    expect(user.tracks.where(tracker_id: 'owntracks-phone').count).to eq(2)
  end
end
