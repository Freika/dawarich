# frozen_string_literal: true

require 'rails_helper'

# End to end: Overland points whose device is certain about the mode (e.g. a
# phone connected to the car) must come out as that mode even at speeds the
# kinematics would call cycling.
RSpec.describe 'Device-certain transportation mode detection' do
  let(:user) { create(:user) }

  # Town traffic: ~15 km/h with a red-light stop in the middle.
  let(:trip) do
    TransportationTraceGenerator.trip(
      legs: [{ mode: :cycling, duration_s: 300, dt_s: 5 },
             { mode: :stationary, duration_s: 60, dt_s: 5 },
             { mode: :cycling, duration_s: 300, dt_s: 5 }],
      start_time: Time.zone.parse('2026-01-05 09:00 UTC'), seed: 7
    )
  end

  def create_track(motion_data)
    track = create(:track, user: user,
                           start_at: Time.zone.at(trip[:points].first[:timestamp]),
                           end_at: Time.zone.at(trip[:points].last[:timestamp]))
    now = Time.current
    Point.insert_all(trip[:points].map do |p|
      { user_id: user.id, track_id: track.id, timestamp: p[:timestamp],
        lonlat: "SRID=4326;POINT(#{p[:lon]} #{p[:lat]})",
        accuracy: p[:accuracy], velocity: p[:velocity].to_s,
        motion_data: motion_data, created_at: now, updated_at: now }
    end)
    track
  end

  def segments_of(track)
    track.track_segments.order(:start_at).to_a
  end

  let(:certain_driving) { { 'motion' => ['driving'], 'motion_confidence' => 1.0 } }

  it 'classifies a certain stretch as driving from the device, stops included' do
    track = create_track(certain_driving)

    Tracks::Reprocessor.reprocess(track)

    segments = segments_of(track)
    expect(segments.map(&:transportation_mode)).to eq(['driving'])
    expect(segments.first.source).to eq('device')
    expect(segments.first.confidence).to eq('high')
    expect(segments.first.start_at.to_i).to eq(trip[:points].first[:timestamp])
    expect(segments.first.end_at.to_i).to eq(trip[:points].last[:timestamp])
    expect(track.reload.dominant_mode).to eq('driving')
  end

  it 'keeps the speed-based result for the same points without motion_confidence' do
    track = create_track({ 'motion' => ['driving'] })

    Tracks::Reprocessor.reprocess(track)

    segments = segments_of(track)
    expect(segments.map(&:source)).not_to include('device')
    expect(segments.map(&:transportation_mode)).to include('cycling')
  end

  it 'mixes certain and uncertain points in one track' do
    track = create_track({ 'motion' => ['driving'] })
    half = trip[:points][trip[:points].size / 2][:timestamp]
    track.points.where('timestamp >= ?', half).update_all(motion_data: certain_driving)

    Tracks::Reprocessor.reprocess(track)

    device = segments_of(track).select { |s| s.source == 'device' }
    expect(device.map(&:transportation_mode)).to eq(['driving'])
    expect(device.first.start_at.to_i).to be_within(35).of(half)
    expect(device.first.end_at.to_i).to eq(trip[:points].last[:timestamp])
    expect(segments_of(track).first.source).not_to eq('device')
  end

  it 'keeps a user correction over certain device hints when re-detecting' do
    track = create_track(certain_driving)
    Tracks::Reprocessor.reprocess(track)
    segment = segments_of(track).first

    result = Tracks::SegmentEditor.new(segment, user).apply_override('cycling')
    expect(result.success?).to be(true)

    Tracks::Reprocessor.reprocess(track)

    segments = segments_of(track)
    expect(segments.map { |s| [s.transportation_mode, s.source] }).to eq([%w[cycling user]])
    expect(segments.first.corrected_at).to be_present
    expect(track.reload.dominant_mode).to eq('cycling')
  end
end
