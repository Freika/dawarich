# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::TileEpoch do
  let(:user_id) { create(:user).id }

  def component(start_time, end_time)
    described_class.etag_component(user_id, start_time.to_i, end_time.to_i)
  end

  it 'uses a tracks-namespaced key prefix, independent of the points prefix' do
    expect(described_class::KEY_PREFIX).to eq('tracks:tile_epoch')
    expect(Points::TileEpoch::KEY_PREFIX).to eq('points:tile_epoch')
  end

  it 'changes the component for bumped years and keeps untouched years stable' do
    covering_before = component(Time.utc(2024, 1, 1), Time.utc(2024, 12, 31))
    excluding_before = component(Time.utc(2019, 1, 1), Time.utc(2019, 12, 31))

    described_class.bump_range(user_id, Time.utc(2024, 6, 1).to_i, Time.utc(2024, 6, 2).to_i)

    expect(component(Time.utc(2024, 1, 1), Time.utc(2024, 12, 31))).not_to eq(covering_before)
    expect(component(Time.utc(2019, 1, 1), Time.utc(2019, 12, 31))).to eq(excluding_before)
  end

  it 'is independent of the points epoch in both directions' do
    tracks_before = component(Time.utc(2024, 1, 1), Time.utc(2024, 12, 31))

    Points::TileEpoch.bump(user_id, timestamps: [Time.utc(2024, 6, 1).to_i])
    expect(component(Time.utc(2024, 1, 1), Time.utc(2024, 12, 31))).to eq(tracks_before)

    points_settled = Points::TileEpoch.etag_component(
      user_id, Time.utc(2024, 1, 1).to_i, Time.utc(2024, 12, 31).to_i
    )
    described_class.bump(user_id, timestamps: [Time.utc(2024, 6, 1).to_i])
    expect(Points::TileEpoch.etag_component(
             user_id, Time.utc(2024, 1, 1).to_i, Time.utc(2024, 12, 31).to_i
           )).to eq(points_settled)
  end

  it 'never raises out of bump when the cache write fails' do
    allow(Rails.cache).to receive(:write).and_raise(Redis::CannotConnectError)

    expect { described_class.bump(user_id, timestamps: [Time.utc(2024, 6, 1).to_i]) }
      .not_to raise_error
  end
end
