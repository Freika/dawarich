# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::MarkValid do
  let(:user) { create(:user, settings: { 'minutes_between_routes' => 30 }) }
  let(:anchor) { Time.utc(2025, 2, 12, 10).to_i }

  def point_at(minutes, track: nil, anomaly: false, tracker_id: 'phone')
    create(:point, user: user, tracker_id: tracker_id, anomaly: anomaly, track: track,
                   timestamp: anchor + (minutes * 60), lonlat: "POINT(#{13.4 + (minutes * 0.001)} 52.5)")
  end

  def track_with(*minutes, tracker_id: 'phone')
    track = create(:track, user: user, tracker_id: tracker_id,
                           start_at: Time.zone.at(anchor + (minutes.min * 60)),
                           end_at: Time.zone.at(anchor + (minutes.max * 60)))
    minutes.each { |m| point_at(m, track: track, tracker_id: tracker_id) }
    track
  end

  it 'clears the anomaly flag and protects the point from the filter' do
    point = point_at(5, anomaly: true)

    described_class.call(user: user, point_id: point.id)

    expect(point.reload).to have_attributes(anomaly: false, anomaly_override: true)
  end

  it 'puts the point back into the track it was cut out of' do
    track = track_with(0, 10)
    point = point_at(5, anomaly: true)

    described_class.call(user: user, point_id: point.id)

    expect(point.reload.track_id).to eq(track.id)
    expect(track.reload.points).to include(point)
  end

  it "re-attaches to its own device's track when another device logged a closer point" do
    track = track_with(0, 10)
    track_with(4, 6, tracker_id: 'watch')
    point = point_at(5, anomaly: true)

    described_class.call(user: user, point_id: point.id)

    expect(point.reload.track_id).to eq(track.id)
  end

  it 'leaves a point that is not an anomaly untouched' do
    point = point_at(5)

    expect do
      described_class.call(user: user, point_id: point.id)
    end.not_to have_enqueued_job(Stats::CalculatingJob)
    expect(point.reload).to have_attributes(anomaly: false, anomaly_override: false)
  end

  it 'does not queue the recalculation again for a point already marked correct' do
    point = point_at(5, anomaly: true)
    described_class.call(user: user, point_id: point.id)

    expect do
      described_class.call(user: user, point_id: point.id)
    end.not_to have_enqueued_job(Stats::CalculatingJob)
  end

  it 'leaves a point with no track nearby untracked' do
    track_with(0, 10)
    point = point_at(120, anomaly: true)

    described_class.call(user: user, point_id: point.id)

    expect(point.reload).to have_attributes(anomaly: false, track_id: nil)
  end

  it 'recalculates the month the point belongs to' do
    point = point_at(5, anomaly: true)

    expect do
      described_class.call(user: user, point_id: point.id)
    end.to have_enqueued_job(Stats::CalculatingJob).with(user.id, 2025, 2)
  end

  it 'invalidates the map tiles so the point shows up again' do
    point = point_at(5, anomaly: true)

    expect do
      described_class.call(user: user, point_id: point.id)
    end.to(change { Points::TileEpoch.etag_component(user.id, point.timestamp, point.timestamp) })
  end

  it "does not touch another user's point" do
    other = create(:point, anomaly: true)

    expect do
      described_class.call(user: user, point_id: other.id)
    end.to raise_error(ActiveRecord::RecordNotFound)
    expect(other.reload.anomaly).to be true
  end
end
