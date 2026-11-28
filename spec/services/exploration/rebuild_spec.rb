# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Exploration::Rebuild do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:dataset) { Exploration::Dataset.create!(version: "test-#{SecureRandom.hex(6)}", completed_at: Time.current) }
  let(:connection) { ApplicationRecord.connection }

  before do
    allow(Exploration::Geography).to receive(:current).and_return(dataset)
    allow(Exploration::Geography).to receive(:install!).and_return(dataset)
    connection.execute(<<~SQL)
      INSERT INTO exploration_territories(dataset_id,code,name,boundary,land,land_area)
      SELECT #{dataset.id},'WEST','West',g,g,ST_Area(g::geography) FROM
      (SELECT ST_Multi(ST_MakeEnvelope(13.30,52.49,13.35,52.53,4326)) g) s;
      INSERT INTO exploration_territories(dataset_id,code,name,boundary,land,land_area)
      SELECT #{dataset.id},'EAST','East',g,g,ST_Area(g::geography) FROM
      (SELECT ST_Multi(ST_MakeEnvelope(13.35,52.49,13.40,52.53,4326)) g) s;
    SQL
  end

  def add_point(timestamp:, lon: 13.34999, lat: 52.514, **attrs)
    Point.insert_all!([{ user_id: user.id, timestamp: timestamp, lonlat: "POINT(#{lon} #{lat})",
                        created_at: Time.current, updated_at: Time.current, **attrs }])
  end

  def rebuild
    described_class.new(user).call
    Exploration::State.find_by!(user_id: user.id).reload
  end

  it 'deduplicates cells, clips at borders and keeps a border opening distinct from a country visit' do
    add_point(timestamp: 100)
    add_point(timestamp: 200)
    state = rebuild
    rows = Exploration::CountryTotal.where(snapshot_id: state.snapshot_id).order(:territory_id)
    expect(Exploration::Opening.where(snapshot_id: state.snapshot_id).count).to eq(1)
    expect(rows.pluck(:visited)).to eq([true, false])
    expect(rows.pluck(:opened_area)).to all(be > 0)
    expect(rows.sum(:opened_area)).to be_within(0.1).of(
      connection.select_value('SELECT ST_Area(geom::geography) FROM exploration_cells LIMIT 1').to_f
    )
  end

  it 'does not open cells or count visits from future observations' do
    add_point(timestamp: 1.day.from_now.to_i)
    state = rebuild

    expect(Exploration::Opening.where(snapshot_id: state.snapshot_id)).to be_empty
    expect(Exploration::CountryTotal.where(snapshot_id: state.snapshot_id, visited: true)).to be_empty
  end

  it 'publishes a first snapshot despite a mid-calculation write and refreshes it after the interval' do
    add_point(timestamp: 100)
    changed = false
    allow(Exploration::Coverage).to receive(:ensure!).and_wrap_original do |method, *args|
      method.call(*args)
      next if changed

      changed = true
      add_point(timestamp: 200)
    end
    state = rebuild
    expect(state.snapshot_id).to be_present
    expect(state.revision).to be > state.published_revision
    clear_enqueued_jobs

    expect { Exploration::RefreshJob.perform_now }.not_to have_enqueued_job(Exploration::RebuildJob)
    travel(Exploration::State::REFRESH_INTERVAL + 1.minute) do
      expect { Exploration::RefreshJob.perform_now }.to have_enqueued_job(Exploration::RebuildJob).with(user.id)
    end
  end

  it 'moves the first opening on old imports and deletes, then closes the last remaining cell' do
    add_point(timestamp: 200)
    state = rebuild
    old_snapshot = state.snapshot_id
    add_point(timestamp: 100)
    state = rebuild
    expect(Exploration::Opening.find_by!(snapshot_id: state.snapshot_id).first_timestamp).to eq(100)
    user.points.where(timestamp: 100).delete_all
    state = rebuild
    expect(Exploration::Opening.find_by!(snapshot_id: state.snapshot_id).first_timestamp).to eq(200)
    user.points.delete_all
    state = rebuild
    expect(Exploration::Opening.where(snapshot_id: state.snapshot_id)).to be_empty
    expect(Exploration::Snapshot.exists?(old_snapshot)).to be(true)
  end

  it 'handles anomaly toggles and coordinate edits made through bulk SQL without filtering unknown accuracy' do
    add_point(timestamp: 100, accuracy: nil)
    state = rebuild
    original = Exploration::Opening.find_by!(snapshot_id: state.snapshot_id).cell_id
    user.points.update_all(anomaly: true)
    expect(Exploration::Opening.where(snapshot_id: rebuild.snapshot_id)).to be_empty
    user.points.update_all(anomaly: false, lonlat: 'POINT(13.39 52.514)')
    expect(Exploration::Opening.find_by!(snapshot_id: rebuild.snapshot_id).cell_id).not_to eq(original)
  end

  it 'publishes the source it read and leaves a later source change dirty' do
    add_point(timestamp: 100)
    rebuild
    add_point(timestamp: 200, lon: 13.39)
    allow(Exploration::Coverage).to receive(:ensure!).and_wrap_original do |method, *args|
      method.call(*args)
      user.points.where(timestamp: 200).update_all(anomaly: true)
    end
    state = rebuild
    timestamps = Exploration::Opening.where(snapshot_id: state.snapshot_id).pluck(:first_timestamp)
    expect(timestamps).to contain_exactly(100, 200)
    expect(state.revision).to be > state.published_revision
  end

  it 'anchors legacy manual corrections before reading the source snapshot' do
    trip = TransportationTraceGenerator.trip(legs: [{ mode: :walking, duration_s: 120, dt_s: 10 }],
                                             start_time: Time.zone.parse('2026-01-05 09:00 UTC'), seed: 7)
    track = create(:track, user: user, start_at: Time.zone.at(trip[:points].first[:timestamp]),
                           end_at: Time.zone.at(trip[:points].last[:timestamp]))
    trip[:points].each do |p|
      create(:point, user: user, track: track, timestamp: p[:timestamp], lonlat: "POINT(#{p[:lon]} #{p[:lat]})")
    end
    segment = create(:track_segment, track: track, transportation_mode: :cycling, corrected_at: 1.week.ago,
                                     start_index: 2, end_index: 5, start_at: nil, end_at: nil)
    anchored = nil
    allow(Exploration::SourceSnapshot).to receive(:call).and_wrap_original do |method, &block|
      anchored = segment.reload.start_at
      method.call(&block)
    end

    rebuild

    expect(anchored).to be_present
  end

  it 'keeps the published generation when the worker fails' do
    add_point(timestamp: 100)
    old = rebuild.snapshot_id
    add_point(timestamp: 200)
    allow(Exploration::Coverage).to receive(:ensure!).and_raise('failed geometry')
    expect { rebuild }.to raise_error('failed geometry')
    state = Exploration::State.find_by!(user_id: user.id)
    expect(state.snapshot_id).to eq(old)
    expect(state.failed_at).to be_present
  end

  it 'does not invalidate exploration for reverse-geocoding-only updates' do
    add_point(timestamp: 100)
    state = rebuild
    expect { user.points.update_all(city: 'Berlin', reverse_geocoded_at: Time.current) }
      .not_to(change { state.reload.revision })
  end

  it 'excludes shared-classifier flights even with flying disabled, and honors manual ground corrections' do
    track = create(:track, user: user)
    user.update!(settings: user.settings.merge('enabled_transportation_modes' => ['walking']))
    add_point(timestamp: track.start_at.to_i, track_id: track.id)
    add_point(timestamp: track.end_at.to_i, track_id: track.id)
    detector = instance_double(TransportationModes::Detector)
    allow(TransportationModes::Detector).to receive(:new).with(track, enabled_modes: Track::TRANSPORTATION_MODES.keys,
preserved: anything, fallback: false).and_return(detector)
    allow(detector).to receive(:call).and_return([{ mode: :flying, start_at: track.start_at, end_at: track.end_at }])
    expect(Exploration::Opening.where(snapshot_id: rebuild.snapshot_id)).to be_empty
    track.track_segments.create!(transportation_mode: :driving, start_at: track.start_at, end_at: track.end_at,
                                 corrected_at: Time.current)
    expect(Exploration::Opening.where(snapshot_id: rebuild.snapshot_id).count).to eq(1)
  end

  it 'calculates new area from exact first timestamps, without changing cumulative totals' do
    add_point(timestamp: 100)
    rebuild
    before = Exploration::Result.new(user, start_at: 100, end_at: 100).call
    after = Exploration::Result.new(user, start_at: 101, end_at: 200).call
    expect(before[:new_area]).to eq(before[:opened_area])
    expect(after[:new_area]).to eq(0)
    expect(after[:opened_area]).to eq(before[:opened_area])
  end

  it 'deduplicates and finds the earliest evidence across batch boundaries' do
    stub_const('Exploration::Rebuild::BATCH_SIZE', 1)
    add_point(timestamp: 300)
    add_point(timestamp: 100)
    add_point(timestamp: 200)
    rows = Exploration::Opening.where(snapshot_id: rebuild.snapshot_id)
    expect(rows.count).to eq(1)
    expect(rows.first.first_timestamp).to eq(100)
    expect(rows.first.point_id).to eq(user.points.find_by!(timestamp: 100).id)
  end

  it 'uses the same water mask for opened land and country land' do
    connection.execute(<<~SQL)
      UPDATE exploration_territories SET land = ST_Multi(ST_Difference(land,
        ST_MakeEnvelope(13.3498,52.5138,13.3502,52.5142,4326))) WHERE dataset_id=#{dataset.id};
      UPDATE exploration_territories SET land_area=ST_Area(land::geography) WHERE dataset_id=#{dataset.id};
    SQL
    add_point(timestamp: 100)
    state = rebuild
    opened = Exploration::CountryTotal.where(snapshot_id: state.snapshot_id).sum(:opened_area)
    cell_area = connection.select_value('SELECT ST_Area(geom::geography) FROM exploration_cells LIMIT 1').to_f
    water_area = connection.select_value(<<~SQL).to_f
      SELECT ST_Area(ST_MakeEnvelope(13.3498,52.5138,13.3502,52.5142,4326)::geography)
    SQL
    expect(opened).to be_within(0.1).of(cell_area - water_area)
  end

  it 'removes private derived data when the owner is deleted' do
    add_point(timestamp: 100)
    snapshot_id = rebuild.snapshot_id
    user.points.delete_all
    User.where(id: user.id).delete_all
    expect(Exploration::State.where(user_id: user.id)).to be_empty
    expect(Exploration::Snapshot.where(user_id: user.id)).to be_empty
    expect(Exploration::Opening.where(snapshot_id: snapshot_id)).to be_empty
    expect(Exploration::CountryTotal.where(snapshot_id: snapshot_id)).to be_empty
  end
end
