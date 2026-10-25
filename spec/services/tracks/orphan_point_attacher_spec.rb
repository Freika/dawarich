# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::OrphanPointAttacher do
  let(:user) { create(:user, settings: { 'minutes_between_routes' => 30 }) }
  let(:anchor) { Time.utc(2025, 2, 12, 10).to_i }

  def point_at(minutes, track: nil)
    create(:point, user: user, tracker_id: 'phone', anomaly: false, track: track,
                   timestamp: anchor + (minutes * 60), lonlat: "POINT(#{-140 + (minutes * 0.001)} -40)")
  end

  def track_with(*minutes)
    track = create(:track, user: user, tracker_id: 'phone',
                           start_at: Time.zone.at(anchor + (minutes.min * 60)),
                           end_at: Time.zone.at(anchor + (minutes.max * 60)))
    minutes.each { |m| point_at(m, track: track) }
    track
  end

  it 'attaches lone points next to two different tracks to their own neighbours' do
    morning = track_with(0, 10)
    noon = track_with(120, 130)
    early = point_at(15)
    late = point_at(125)
    segment = Point.where(user: user).order(:timestamp).to_a

    described_class.new(user, [early, late], segment).call

    expect(early.reload.track_id).to eq(morning.id)
    expect(late.reload.track_id).to eq(noon.id)
  end

  it 'leaves a lone point too far from its neighbour untracked and still attaches the others' do
    track = track_with(0, 10)
    near = point_at(15)
    far = point_at(90)
    segment = Point.where(user: user).order(:timestamp).to_a

    described_class.new(user, [near, far], segment).call

    expect(near.reload.track_id).to eq(track.id)
    expect(far.reload.track_id).to be_nil
  end

  it 'keeps attaching to other tracks when refreshing one track fails' do
    failing = track_with(0, 10)
    healthy = track_with(120, 130)
    first = point_at(15)
    second = point_at(125)
    segment = Point.where(user: user).order(:timestamp).to_a
    allow(Tracks::Reprocessor).to receive(:reprocess).and_wrap_original do |original, track|
      raise ActiveRecord::StatementInvalid, 'boom' if track.id == failing.id

      original.call(track)
    end

    expect { described_class.new(user, [first, second], segment).call }.not_to raise_error
    expect(second.reload.track_id).to eq(healthy.id)
    expect(first.reload.track_id).to be_nil
  end
end
