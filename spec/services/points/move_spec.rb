# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::Move do
  let(:user) { create(:user) }
  let(:track) do
    create(:track, user:, start_at: Time.zone.at(1_000), end_at: Time.zone.at(1_120),
                   original_path: 'LINESTRING(0 0, 0.02 0)')
  end
  let!(:point) { create(:point, user:, track:, timestamp: 1_000, longitude: 0, latitude: 0) }
  let!(:other_point) { create(:point, user:, track:, timestamp: 1_120, longitude: 0.02, latitude: 0) }
  let(:scope) { { start_at: 900, end_at: 1_200, import_id: nil } }

  before do
    allow(MapEdits::Publisher).to receive(:call)
  end

  it 'atomically moves the point and returns canonical recalculated track state' do
    allow(TracksChannel).to receive(:broadcast_to)

    result = described_class.call(
      user:, point_id: point.id, latitude: 0.01, longitude: 0.01,
      point_revision: point.lock_version, track_revision: track.lock_version,
      history_scope: scope
    )

    expect(result.point).to have_attributes(lat: 0.01, lon: 0.01, lock_version: 1)
    expect(result.track.original_path.points.map { |item| [item.x, item.y] }).to eq([[0.01, 0.01], [0.02, 0.0]])
    expect(result.track_revision).to eq(1)
    expect(MapEdits::Publisher).to have_received(:call).with(user:, result:)
    expect(TracksChannel).not_to have_received(:broadcast_to)
  end

  it "enqueues a monthly stats recalculation for the moved point's month" do
    expect do
      described_class.call(
        user:, point_id: point.id, latitude: 0.01, longitude: 0.01,
        point_revision: point.lock_version, track_revision: track.lock_version,
        history_scope: scope
      )
    end.to have_enqueued_job(Stats::CalculatingJob).with(user.id, 1970, 1)
  end

  it 'returns the committed move and publishes it when the stats job cannot be enqueued' do
    allow(Stats::CalculatingJob).to receive(:perform_later).and_raise(Redis::CannotConnectError)
    allow(ExceptionReporter).to receive(:call)

    result = nil
    expect do
      result = described_class.call(
        user:, point_id: point.id, latitude: 0.01, longitude: 0.01,
        point_revision: point.lock_version, track_revision: track.lock_version,
        history_scope: scope
      )
    end.to increment_yabeda_counter(Yabeda.dawarich_map.post_commit_failures_total)
      .with_tags(operation: 'stats')

    expect(result.point).to have_attributes(lat: 0.01, lon: 0.01, lock_version: 1)
    expect(MapEdits::Publisher).to have_received(:call).with(user:, result:)
  end

  it "picks the stats month in the user's timezone" do
    user.update!(settings: user.settings.merge('timezone' => 'Asia/Tokyo'))
    boundary_timestamp = Time.utc(2026, 1, 31, 20, 0).to_i
    boundary_point = create(:point, user:, timestamp: boundary_timestamp, longitude: 5, latitude: 5)

    expect do
      described_class.call(
        user:, point_id: boundary_point.id, latitude: 5.01, longitude: 5.01,
        point_revision: boundary_point.lock_version, track_revision: nil,
        history_scope: { start_at: boundary_timestamp - 60, end_at: boundary_timestamp + 60, import_id: nil }
      )
    end.to have_enqueued_job(Stats::CalculatingJob).with(user.id, 2026, 2)
  end

  it 'returns canonical state and does not mutate on a stale point revision' do
    expect do
      described_class.call(
        user:, point_id: point.id, latitude: 1, longitude: 1,
        point_revision: point.lock_version + 1, track_revision: track.lock_version,
        history_scope: scope
      )
    end.to raise_error(Points::Move::StaleEdit) { |error| expect(error.result.point.lon).to eq(point.lon) }

    expect(point.reload.lon).to eq(0.0)
  end

  it 'rolls the point back when track recalculation fails' do
    segment = create(:track_segment, track:, start_index: 0, end_index: 1, distance: 100)
    allow(Tracks::Recalculator).to receive(:call).and_raise(ActiveRecord::RecordInvalid.new(track))

    expect do
      described_class.call(
        user:, point_id: point.id, latitude: 1, longitude: 1,
        point_revision: point.lock_version, track_revision: track.lock_version,
        history_scope: scope
      )
    end.to raise_error(ActiveRecord::RecordInvalid)

    expect(point.reload).to have_attributes(lon: 0.0, lat: 0.0, lock_version: 0)
    expect(track.reload.lock_version).to eq(0)
    expect(segment.reload.distance).to eq(100)
  end

  it 'rolls point, track, segments, and revisions back when the hard budget expires' do
    segment = create(:track_segment, track:, start_index: 0, end_index: 1, distance: 100)
    allow(Rails.logger).to receive(:warn)
    allow(Tracks::Recalculator).to receive(:call) do |locked_track, **|
      locked_track.update!(distance: 999)
      segment.update!(distance: 999)
      raise Timeout::Error, 'execution expired'
    end

    expect do
      described_class.call(
        user:, point_id: point.id, latitude: 1, longitude: 1,
        point_revision: point.lock_version, track_revision: track.lock_version,
        history_scope: scope
      )
    end.to raise_error(Points::Move::RecalculationTimeout)

    expect(point.reload).to have_attributes(lon: 0.0, lat: 0.0, lock_version: 0)
    expect(track.reload).to have_attributes(distance: 1_500, lock_version: 0)
    expect(segment.reload.distance).to eq(100)
    expect(Rails.logger).to have_received(:warn).with(
      /event=point_move\.timeout outcome=timeout error_class=Timeout::Error/
    )
  end

  it 'supports trackless points' do
    trackless = create(:point, user:, timestamp: 1_050, longitude: 0.5, latitude: 0.5)

    result = described_class.call(
      user:, point_id: trackless.id, latitude: 0.6, longitude: 0.6,
      point_revision: trackless.lock_version, track_revision: nil,
      history_scope: scope
    )

    expect(result.track).to be_nil
    expect(result.point.lon).to eq(0.6)
  end

  it 'returns the committed edit when post-commit tile invalidation fails' do
    allow(Points::TileEpoch).to receive(:bump).and_raise('cache unavailable')
    allow(ExceptionReporter).to receive(:call)

    result = nil
    expect do
      result = described_class.call(
        user:, point_id: point.id, latitude: 0.01, longitude: 0.01,
        point_revision: point.lock_version, track_revision: track.lock_version,
        history_scope: scope
      )
    end.to increment_yabeda_counter(Yabeda.dawarich_map.post_commit_failures_total)
      .with_tags(operation: 'publish')

    expect(result.point.reload).to have_attributes(lat: 0.01, lon: 0.01)
    expect(ExceptionReporter).to have_received(:call)
  end

  it 'emits success count and duration metrics without location labels' do
    move = lambda do
      described_class.call(
        user:, point_id: point.id, latitude: 0.01, longitude: 0.01,
        point_revision: point.lock_version, track_revision: track.lock_version,
        history_scope: scope
      )
    end

    expect(&move).to increment_yabeda_counter(Yabeda.dawarich_map.point_moves_total)
      .with_tags(outcome: 'success')
  end

  it 'emits conflict count when a stale revision is rejected' do
    allow(Rails.logger).to receive(:info)
    stale_move = lambda do
      described_class.call(
        user:, point_id: point.id, latitude: 0.01, longitude: 0.01,
        point_revision: point.lock_version + 1, track_revision: track.lock_version,
        history_scope: scope
      )
    rescue Points::Move::StaleEdit
      nil
    end

    expect(&stale_move).to increment_yabeda_counter(Yabeda.dawarich_map.point_moves_total)
      .with_tags(outcome: 'conflict')
    expect(Rails.logger).to have_received(:info).with('event=point_move.conflict outcome=conflict')
  end

  it 'measures move duration, lock wait, point count, and segment count' do
    expect do
      described_class.call(
        user:, point_id: point.id, latitude: 0.01, longitude: 0.01,
        point_revision: point.lock_version, track_revision: track.lock_version,
        history_scope: scope
      )
    end.to measure_yabeda_histogram(Yabeda.dawarich_map.point_move_duration_seconds)
  end

  it 'updates country membership synchronously when crossing a border' do
    germany = create(:country, name: 'Germany', iso_a2: 'DE', iso_a3: 'DEU',
                               geom: 'MULTIPOLYGON (((-1 -1, 1 -1, 1 1, -1 1, -1 -1)))')
    create(:country, name: 'France', iso_a2: 'FR', iso_a3: 'FRA',
                     geom: 'MULTIPOLYGON (((2 -1, 4 -1, 4 1, 2 1, 2 -1)))')
    point.update_columns(country_id: germany.id, country_name: germany.name, country: germany.name)

    result = described_class.call(
      user:, point_id: point.id, latitude: 0, longitude: 3,
      point_revision: point.reload.lock_version, track_revision: track.reload.lock_version,
      history_scope: scope
    )

    expect(result.point.country_name).to eq('France')
    expect(result.visited_countries).to eq(iso_a3: ['FRA'])
  end

  it 'rejects a stale track revision even when the point revision is current' do
    expect do
      described_class.call(
        user:, point_id: point.id, latitude: 1, longitude: 1,
        point_revision: point.lock_version, track_revision: track.lock_version + 1,
        history_scope: scope
      )
    end.to raise_error(Points::Move::StaleEdit)

    expect(point.reload.lon).to eq(0.0)
  end

  describe 'input validation' do
    invalid_coordinates = {
      'NaN latitude' => ['NaN', 0],
      'infinite latitude' => [Float::INFINITY, 0],
      'latitude above 90' => [90.0001, 0],
      'latitude below -90' => [-90.0001, 0],
      'longitude above 180' => [0, 180.0001],
      'longitude below -180' => [0, -180.0001]
    }

    invalid_coordinates.each do |description, (latitude, longitude)|
      it "rejects #{description}" do
        expect do
          described_class.call(
            user:, point_id: point.id, latitude:, longitude:,
            point_revision: point.lock_version, track_revision: track.lock_version,
            history_scope: scope
          )
        end.to raise_error(Points::Move::InvalidCoordinates)

        expect(point.reload).to have_attributes(lon: 0.0, lat: 0.0, lock_version: 0)
      end
    end

    it 'rejects a reversed or incomplete history scope' do
      [
        { start_at: 1_200, end_at: 900 },
        { start_at: 900 },
        { end_at: 1_200 }
      ].each do |history_scope|
        expect do
          described_class.call(
            user:, point_id: point.id, latitude: 1, longitude: 1,
            point_revision: point.lock_version, track_revision: track.lock_version,
            history_scope: history_scope
          )
        end.to raise_error(Points::Move::InvalidHistoryScope)
      end
    end
  end

  it 'does not report a country set change when both memberships remain visited' do
    germany = create(:country, name: 'Germany', iso_a2: 'DE', iso_a3: 'DEU',
                               geom: 'MULTIPOLYGON (((-1 -1, 1 -1, 1 1, -1 1, -1 -1)))')
    france = create(:country, name: 'France', iso_a2: 'FR', iso_a3: 'FRA',
                              geom: 'MULTIPOLYGON (((2 -1, 4 -1, 4 1, 2 1, 2 -1)))')
    point.update_columns(country_id: germany.id, country_name: germany.name, country: germany.name)
    other_point.update_columns(country_id: germany.id, country_name: germany.name, country: germany.name)
    create(:point, user:, timestamp: 1_060, longitude: 3.5, latitude: 0,
                   country_id: france.id, country_name: france.name, country: france.name)

    result = described_class.call(
      user:, point_id: point.id, latitude: 0, longitude: 3,
      point_revision: point.reload.lock_version, track_revision: track.reload.lock_version,
      history_scope: scope
    )

    expect(result.visited_countries).to be_nil
  end
end
