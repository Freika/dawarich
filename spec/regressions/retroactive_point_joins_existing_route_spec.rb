# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'A retroactive API point joins the existing historical route', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:anchor) { 1.year.ago.beginning_of_day + 10.hours }
  let(:tracker_id) { 'synthetic-ocean-device' }
  let(:generation_jobs) do
    [Tracks::BackfillGenerationJob, Tracks::ParallelGeneratorJob,
     Tracks::TimeChunkProcessorJob, Tracks::BoundaryResolverJob]
  end

  def post_point(lon, lat, at, device: tracker_id)
    post api_v1_points_url(api_key: user.api_key), params: {
      locations: [{
        type: 'Feature',
        geometry: { type: 'Point', coordinates: [lon, lat] },
        properties: { timestamp: at.iso8601, device_id: device }.compact
      }]
    }, as: :json
    expect(response).to be_successful
  end

  def run_generation_jobs
    10.times do
      break if enqueued_jobs.none? { |job| generation_jobs.map(&:name).include?(job['job_class']) }

      perform_enqueued_jobs(only: generation_jobs)
    end
  end

  it 'adds the late point to the existing route and keeps the route' do
    Points::Intake.call(user_id: user.id, mode: :bulk, payloads: [
                          { timestamp: anchor.to_i, lonlat: 'POINT(-140.020 -40.000)', tracker_id: tracker_id },
                          { timestamp: (anchor + 10.minutes).to_i, lonlat: 'POINT(-140.000 -40.000)',
                            tracker_id: tracker_id }
                        ])
    perform_enqueued_jobs(only: generation_jobs) do
      Tracks::ParallelGeneratorJob.perform_later(user.id, start_at: anchor.beginning_of_day, end_at: anchor.end_of_day)
    end
    route = user.tracks.sole
    shared_link = create(:shared_link, user: user, resource_type: :track, resource_id: route.id)

    post_point(-140.010, -39.990, anchor + 5.minutes)
    travel 2.minutes
    run_generation_jobs

    late_point = user.points.find_by!(timestamp: (anchor + 5.minutes).to_i)
    aggregate_failures do
      expect(user.tracks.reload.sole.id).to eq(route.id)
      expect(late_point.reload.track_id).to eq(route.id)
      expect(route.reload.original_path.points.map { |point| [point.x, point.y] }).to eq(
        [[-140.020, -40.000], [-140.010, -39.990], [-140.000, -40.000]]
      )
      expect(SharedLink.exists?(shared_link.id)).to be(true)
    end
  ensure
    travel_back
  end

  it 'adds several late points in the middle of a long route and keeps the route' do
    Points::Intake.call(user_id: user.id, mode: :bulk, payloads: [
                          { timestamp: anchor.to_i, lonlat: 'POINT(-140.300 -40.000)', tracker_id: tracker_id },
                          { timestamp: (anchor + 20.minutes).to_i, lonlat: 'POINT(-140.000 -40.000)',
                            tracker_id: tracker_id }
                        ])
    perform_enqueued_jobs(only: generation_jobs) do
      Tracks::ParallelGeneratorJob.perform_later(user.id, start_at: anchor.beginning_of_day, end_at: anchor.end_of_day)
    end
    route = user.tracks.sole
    shared_link = create(:shared_link, user: user, resource_type: :track, resource_id: route.id)

    post_point(-140.160, -39.990, anchor + 9.minutes)
    post_point(-140.140, -39.990, anchor + 11.minutes)
    travel 2.minutes
    run_generation_jobs

    aggregate_failures do
      expect(user.tracks.reload.pluck(:id)).to eq([route.id])
      expect(user.points.where(track_id: nil)).to be_empty
      expect(route.reload.original_path.points.size).to eq(4)
      expect(SharedLink.exists?(shared_link.id)).to be(true)
    end
  ensure
    travel_back
  end

  it 'keeps a late batch far away from the route as its own track' do
    Points::Intake.call(user_id: user.id, mode: :bulk, payloads: [
                          { timestamp: anchor.to_i, lonlat: 'POINT(-140.300 -40.000)', tracker_id: tracker_id },
                          { timestamp: (anchor + 20.minutes).to_i, lonlat: 'POINT(-140.000 -40.000)',
                            tracker_id: tracker_id }
                        ])
    perform_enqueued_jobs(only: generation_jobs) do
      Tracks::ParallelGeneratorJob.perform_later(user.id, start_at: anchor.beginning_of_day, end_at: anchor.end_of_day)
    end
    route = user.tracks.sole

    post_point(-140.160, -39.500, anchor + 9.minutes)
    post_point(-140.140, -39.500, anchor + 11.minutes)
    travel 2.minutes
    run_generation_jobs

    aggregate_failures do
      expect(user.tracks.reload.count).to eq(2)
      expect(route.reload.original_path.points.size).to eq(2)
    end
  ensure
    travel_back
  end

  it 'adds two late batches far apart in time inside one long route' do
    Points::Intake.call(user_id: user.id, mode: :bulk, payloads: (0..10).map do |step|
      { timestamp: (anchor + (step * 25).minutes).to_i, lonlat: "POINT(#{-140.300 + (step * 0.03)} -40.000)",
        tracker_id: tracker_id }
    end)
    perform_enqueued_jobs(only: generation_jobs) do
      Tracks::ParallelGeneratorJob.perform_later(user.id, start_at: anchor.beginning_of_day, end_at: anchor.end_of_day)
    end
    route = user.tracks.sole

    post_point(-140.255, -39.995, anchor + 37.minutes)
    post_point(-140.254, -39.995, anchor + 38.minutes)
    post_point(-140.045, -39.995, anchor + 212.minutes)
    post_point(-140.044, -39.995, anchor + 213.minutes)
    travel 2.minutes
    run_generation_jobs

    aggregate_failures do
      expect(user.tracks.reload.pluck(:id)).to eq([route.id])
      expect(user.points.where(track_id: nil)).to be_empty
    end
  ensure
    travel_back
  end

  it 'joins a late batch without a device in the middle of a route without a device' do
    Points::Intake.call(user_id: user.id, mode: :bulk, payloads: [
                          { timestamp: anchor.to_i, lonlat: 'POINT(-140.300 -40.000)' },
                          { timestamp: (anchor + 20.minutes).to_i, lonlat: 'POINT(-140.000 -40.000)' }
                        ])
    perform_enqueued_jobs(only: generation_jobs) do
      Tracks::ParallelGeneratorJob.perform_later(user.id, start_at: anchor.beginning_of_day, end_at: anchor.end_of_day)
    end
    route = user.tracks.sole

    post_point(-140.160, -39.990, anchor + 9.minutes, device: nil)
    post_point(-140.140, -39.990, anchor + 11.minutes, device: nil)
    travel 2.minutes
    run_generation_jobs

    aggregate_failures do
      expect(user.tracks.reload.pluck(:id)).to eq([route.id])
      expect(user.points.where(track_id: nil)).to be_empty
    end
  ensure
    travel_back
  end

  it 'extends the route in place when a late batch starts before it' do
    Points::Intake.call(user_id: user.id, mode: :bulk, payloads: [
                          { timestamp: anchor.to_i, lonlat: 'POINT(-140.300 -40.000)', tracker_id: tracker_id },
                          { timestamp: (anchor + 20.minutes).to_i, lonlat: 'POINT(-140.000 -40.000)',
                            tracker_id: tracker_id }
                        ])
    perform_enqueued_jobs(only: generation_jobs) do
      Tracks::ParallelGeneratorJob.perform_later(user.id, start_at: anchor.beginning_of_day, end_at: anchor.end_of_day)
    end
    route = user.tracks.sole
    shared_link = create(:shared_link, user: user, resource_type: :track, resource_id: route.id)
    route.track_segments.first.update!(transportation_mode: :cycling, corrected_at: Time.current)

    post_point(-140.320, -40.000, anchor - 6.minutes)
    post_point(-140.310, -40.000, anchor - 3.minutes)
    travel 2.minutes
    run_generation_jobs

    aggregate_failures do
      expect(user.tracks.reload.pluck(:id)).to eq([route.id])
      expect(route.reload.start_at).to eq(anchor - 6.minutes)
      expect(SharedLink.exists?(shared_link.id)).to be(true)
      expect(route.track_segments.manually_corrected.pluck(:transportation_mode)).to include('cycling')
    end
  ensure
    travel_back
  end

  it 'extends the route in place when a late batch starts before it and ends after it' do
    Points::Intake.call(user_id: user.id, mode: :bulk, payloads: [
                          { timestamp: (anchor + 5.minutes).to_i, lonlat: 'POINT(-140.300 -40.000)',
                            tracker_id: tracker_id },
                          { timestamp: (anchor + 15.minutes).to_i, lonlat: 'POINT(-140.280 -40.000)',
                            tracker_id: tracker_id }
                        ])
    perform_enqueued_jobs(only: generation_jobs) do
      Tracks::ParallelGeneratorJob.perform_later(user.id, start_at: anchor.beginning_of_day, end_at: anchor.end_of_day)
    end
    route = user.tracks.sole
    shared_link = create(:shared_link, user: user, resource_type: :track, resource_id: route.id)

    post_point(-140.310, -40.000, anchor)
    post_point(-140.270, -40.000, anchor + 20.minutes)
    travel 2.minutes
    run_generation_jobs

    aggregate_failures do
      expect(user.tracks.reload.pluck(:id)).to eq([route.id])
      expect(route.reload.start_at).to eq(anchor)
      expect(route.end_at).to eq(anchor + 20.minutes)
      expect(user.points.pluck(:track_id).uniq).to eq([route.id])
      expect(SharedLink.exists?(shared_link.id)).to be(true)
    end
  ensure
    travel_back
  end
end
