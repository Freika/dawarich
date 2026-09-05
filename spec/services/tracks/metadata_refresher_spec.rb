# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::MetadataRefresher do
  let(:user) { create(:user) }
  let(:base_time) { Time.utc(2026, 7, 17) }
  let!(:track) do
    create(:track, user: user, start_at: base_time, end_at: base_time + 2.hours,
                   created_at: 2.days.ago)
  end
  let!(:points) do
    [0, 30, 60].map do |minutes|
      create(:point, user: user, track: track, timestamp: (base_time + minutes.minutes).to_i,
                     lonlat: "POINT(#{13 + minutes * 0.001} 52)", altitude: minutes)
    end
  end

  it 'preserves the track, its share and a manual correction crossing the trimmed boundary' do
    link = create(:shared_link, user: user, resource_type: :track, resource_id: track.id)
    correction = create(:track_segment, :anchored, track: track, source: 'manual',
                                                   corrected_at: Time.current,
                                                   start_at: base_time + 30.minutes,
                                                   end_at: base_time + 90.minutes)
    original = correction.attributes

    described_class.new(user).call

    expect(track.reload.end_at).to eq(base_time + 1.hour)
    expect(link.reload.resource_id).to eq(track.id)
    expect(correction.reload.attributes).to eq(original)
    expect(track.elevation_gain).to eq(60)
  end

  it 'does no writes when the finalizer runs again' do
    described_class.new(user).call
    original = track.reload.attributes
    segments = track.track_segments.order(:id).map(&:attributes)
    expect(Tracks::Reprocessor).not_to receive(:reprocess)

    described_class.new(user).call

    expect(track.reload.attributes).to eq(original)
    expect(track.track_segments.order(:id).map(&:attributes)).to eq(segments)
  end

  it 'rolls back all metrics and automatic segments when detection fails' do
    segment = create(:track_segment, :anchored, track: track, start_at: base_time, end_at: track.end_at)
    original = track.reload.attributes
    detector = instance_double(TransportationModes::Detector)
    allow(TransportationModes::Detector).to receive(:new).and_return(detector)
    allow(detector).to receive(:call).and_raise('synthetic detection failure')

    expect { described_class.new(user).call }.to raise_error('synthetic detection failure')

    expect(track.reload.attributes).to eq(original)
    expect(TrackSegment.exists?(segment.id)).to be(true)
  end

  it 'rolls back rather than overwrite another track when corrected bounds collide' do
    other = create(:track, user: user, start_at: base_time, end_at: base_time + 1.hour)
    original = track.reload.attributes

    result = described_class.new(user).call

    expect(result).to include(skipped: 1, reasons: { bounds_collision: 1 }, sample_ids: [track.id])
    expect(track.reload.attributes).to eq(original)
    expect(Track.exists?(other.id)).to be(true)
    expect(points.map { |point| point.reload.track_id }.uniq).to eq([track.id])
  end

  it 'preserves a one-point track when a valid replacement path cannot be built' do
    track.points.where.not(id: points.first.id).delete_all
    original = track.reload.attributes

    result = described_class.new(user).call

    expect(result).to include(skipped: 1, reasons: { insufficient_points: 1 }, sample_ids: [track.id])
    expect(track.reload.attributes).to eq(original)
    expect(points.first.reload.track_id).to eq(track.id)
  end

  it 'does not touch empty tracks or another user’s tracks' do
    track.points.delete_all
    other = create(:track)
    original = [track.reload.attributes, other.attributes]

    described_class.new(user).call

    expect([track.reload.attributes, other.reload.attributes]).to eq(original)
  end
end
