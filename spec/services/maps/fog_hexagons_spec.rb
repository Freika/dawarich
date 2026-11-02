# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Maps::FogHexagons do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:dataset) { Exploration::Dataset.create!(version: 'fog-test', completed_at: Time.current) }
  let(:from) { Time.utc(2024, 6, 1) }
  let(:to) { from.end_of_month }

  before do
    allow(Exploration::Geography).to receive_messages(current: dataset, install!: dataset)
  end

  def point(timestamp:, lon: 13.35)
    Point.insert_all!([{ user_id: user.id, timestamp: timestamp.to_i, lonlat: "POINT(#{lon} 52.51)",
                        created_at: Time.current, updated_at: Time.current }])
  end

  def result(masker = nil)
    described_class.new(user: user, start_date: from, end_date: to, privacy_zone_masker: masker).call
  end

  it 'reports calculation instead of showing a false zero for an unbuilt ledger' do
    expect(result['metadata']).to include('status' => 'calculating', 'snapshot_id' => nil)
  end

  it 'keeps old cells open and highlights only first discoveries inside the selected period' do
    point(timestamp: from - 1.day)
    point(timestamp: from + 1.day)
    point(timestamp: from + 2.days, lon: 13.4)
    Exploration::Rebuild.new(user).call
    old = Exploration::CellGeometry.id(52.51, 13.35)
    fresh = Exploration::CellGeometry.id(52.51, 13.4)
    expect(result['h3_indexes']).to contain_exactly(old, fresh)
    expect(result['new_h3_indexes']).to eq([fresh])
    expect(result['metadata']['status']).to eq('ready')
  end

  it 'keeps the previous consistent snapshot until the refresh interval, then closes cells after deletion' do
    point(timestamp: from)
    Exploration::Rebuild.new(user).call
    user.points.delete_all
    expect(result['metadata']['status']).to eq('ready')
    expect(result['h3_indexes'].size).to eq(1)
    travel(Exploration::State::REFRESH_INTERVAL + 1.minute) do
      expect(result['metadata']['status']).to eq('updating')
      Exploration::Rebuild.new(user).call
      expect(result['h3_indexes']).to be_empty
    end
  end

  it 'masks every touching cell, including cells whose recorded point is outside the zone' do
    point(timestamp: from)
    point(timestamp: from, lon: 13.4)
    Exploration::Rebuild.new(user).call
    center = Exploration::CellGeometry.id(52.51, 13.35)
    boundary_lat, boundary_lon = H3.to_boundary(center.to_i(16)).first
    circle = Maps::PrivacyZoneMasker::Circle.new(lon: boundary_lon, lat: boundary_lat, radius: 20)
    masker = Maps::PrivacyZoneMasker.new(user, circles: [circle])
    expect(masker.in_zone?(13.35, 52.51)).to be(false)
    expect(result(masker)['h3_indexes']).to eq([Exploration::CellGeometry.id(52.51, 13.4)])
  end

  it 'pins a city deep link to its owned snapshot while newer progress is published' do
    point(timestamp: from)
    Exploration::Rebuild.new(user).call
    old_id = result['metadata']['snapshot_id']
    point(timestamp: from + 1.day, lon: 13.4)
    Exploration::Rebuild.new(user).call
    pinned = described_class.new(user: user, start_date: from, end_date: to, snapshot_id: old_id).call
    expect(pinned['metadata']).to include('snapshot_id' => old_id, 'status' => 'ready', 'pinned' => true)
    expect(pinned['h3_indexes'].size).to eq(1)
    expect(result['h3_indexes'].size).to eq(2)
    other = create(:user)
    expect do
      described_class.new(user: other, start_date: from, end_date: to, snapshot_id: old_id).call
    end.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'cannot read another users snapshot' do
    other = create(:user)
    snapshot = Exploration::Snapshot.create!(user_id: other.id, dataset_id: dataset.id, revision: 1,
                                             completed_at: Time.current)
    Exploration::State.create!(user_id: user.id, snapshot_id: snapshot.id)
    expect(result['metadata']['snapshot_id']).to be_nil
  end
end
