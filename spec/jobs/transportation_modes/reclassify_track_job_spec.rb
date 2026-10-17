# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TransportationModes::ReclassifyTrackJob do
  let(:user) { create(:user) }

  def create_track_with_points(legs: [{ mode: :walking, duration_s: 300, dt_s: 5 }])
    trip = TransportationTraceGenerator.trip(
      legs: legs, start_time: Time.zone.parse('2026-01-05 09:00 UTC'), seed: 11
    )
    track = create(:track, user: user,
                           start_at: Time.zone.at(trip[:points].first[:timestamp]),
                           end_at: Time.zone.at(trip[:points].last[:timestamp]))
    now = Time.current
    Point.insert_all(trip[:points].map do |p|
      { user_id: user.id, track_id: track.id, timestamp: p[:timestamp],
        lonlat: "SRID=4326;POINT(#{p[:lon]} #{p[:lat]})",
        accuracy: p[:accuracy], velocity: p[:velocity].to_s,
        created_at: now, updated_at: now }
    end)
    track
  end

  it 'replaces auto segments with fresh time-anchored detection' do
    track = create_track_with_points
    stale = create(:track_segment, track: track, transportation_mode: :flying,
                                   start_index: 0, end_index: 5)

    described_class.perform_now(track.id)

    segments = track.track_segments.reload
    expect(segments.where(id: stale.id)).to be_empty
    expect(segments.pluck(:transportation_mode).uniq).to eq(['walking'])
    expect(segments.first.start_at).to be_present
    expect(track.reload.dominant_mode).to eq('walking')
  end

  it 'preserves manually corrected segments' do
    track = create_track_with_points
    corrected = create(:track_segment, :anchored, track: track,
                                                  transportation_mode: :bus, corrected_at: 1.day.ago)

    described_class.perform_now(track.id)

    expect(TrackSegment.exists?(corrected.id)).to be true
  end

  it 'silently skips missing tracks' do
    expect { described_class.perform_now(-1) }.not_to raise_error
  end

  it 'reports progress when asked' do
    track = create_track_with_points
    status = Tracks::TransportationRecalculationStatus.new(user.id)
    status.start(total_tracks: 1)

    described_class.perform_now(track.id, report_progress: true)

    expect(status.data['processed_tracks']).to eq(1)
    expect(status.current_status).to eq('completed')
  end

  it 'Oban-owned forwards without reporting progress' do
    track = create_track_with_points
    job_owner!(described_class::OWNER_KEY, :oban)
    status = instance_double(Tracks::TransportationRecalculationStatus)
    allow(status).to receive(:increment_processed!)
    allow(Tracks::TransportationRecalculationStatus).to receive(:new).and_return(status)
    job = described_class.new(track.id, report_progress: true, user_id: user.id)

    job.perform_now

    expect(status).not_to have_received(:increment_processed!)
    expect(JobOutbox.sole).to have_attributes(command_type: 'transportation.reclassify_track', aggregate_id: track.id,
                                              event_id: job.job_id,
                                              payload: hash_including('report_progress' => true, 'user_id' => user.id))
  end

  it 'Sidekiq-owned still reports in ensure on failure' do
    track = create_track_with_points
    status = Tracks::TransportationRecalculationStatus.new(user.id)
    status.start(total_tracks: 1)
    allow(TransportationModes::FeatureExtractor).to receive(:call).and_raise(ActiveRecord::StatementInvalid)

    expect do
      described_class.perform_now(track.id, report_progress: true, user_id: user.id)
    end.to raise_error(ActiveRecord::StatementInvalid)

    expect(status.current_status).to eq('completed')
  end

  it 'preserves existing segments when detection fails instead of overwriting with unknown' do
    track = create_track_with_points
    described_class.perform_now(track.id)
    before_ids = track.track_segments.reload.pluck(:id)
    allow(TransportationModes::FeatureExtractor).to receive(:call).and_raise(ActiveRecord::StatementInvalid)

    expect { described_class.perform_now(track.id) }.to raise_error(ActiveRecord::StatementInvalid)

    expect(track.track_segments.reload.pluck(:id)).to match_array(before_ids)
  end

  it 'still counts progress when the track was deleted mid-run' do
    status = Tracks::TransportationRecalculationStatus.new(user.id)
    status.start(total_tracks: 1)

    described_class.perform_now(-1, report_progress: true, user_id: user.id)

    expect(status.current_status).to eq('completed')
  end
end
