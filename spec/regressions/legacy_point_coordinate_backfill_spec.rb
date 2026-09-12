# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260714090000_drop_legacy_lat_lon_from_points.rb')

RSpec.describe 'Legacy point coordinate backfill', :non_transactional do
  let(:connection) { ActiveRecord::Base.connection }
  let(:user) { create(:user) }
  let(:import) { create(:import, user:) }
  let(:timestamp) { Time.utc(2026, 1, 15, 12).to_i }
  let(:longitude) { 13.405 }
  let(:latitude) { 52.52 }

  before do
    connection.add_column(:points, :latitude, :decimal, precision: 10, scale: 6)
    connection.add_column(:points, :longitude, :decimal, precision: 10, scale: 6)
  end

  after do
    connection.remove_column(:points, :latitude) if connection.column_exists?(:points, :latitude)
    connection.remove_column(:points, :longitude) if connection.column_exists?(:points, :longitude)
  end

  it 'finishes when a legacy-only row duplicates an already-backfilled point' do
    stub_const('DropLegacyLatLonFromPoints::BATCH_SIZE', 1)
    existing = create(:point, user:, import:, timestamp:, lonlat: "POINT(#{longitude} #{latitude})")
    backfill_id = connection.select_value(<<~SQL.squish)
      INSERT INTO points (user_id, import_id, timestamp, latitude, longitude, lonlat, created_at, updated_at)
      VALUES (#{user.id}, #{import.id}, #{timestamp + 1}, 48.8566, 2.3522, NULL, NOW(), NOW())
      RETURNING id
    SQL
    legacy_id = connection.select_value(<<~SQL.squish)
      INSERT INTO points (user_id, import_id, timestamp, latitude, longitude, lonlat, created_at, updated_at)
      VALUES (#{user.id}, #{import.id}, #{timestamp}, #{latitude}, #{longitude}, NULL, NOW(), NOW())
      RETURNING id
    SQL

    user.update_column(:points_count, 3)
    import.update_column(:points_count, 3)

    expect { DropLegacyLatLonFromPoints.new.up }.not_to raise_error
    expect(Point.where(id: [existing.id, backfill_id, legacy_id]).count).to eq(2)
    expect(Point.find(backfill_id).lonlat.x).to eq(2.3522)
    expect(Point.find(backfill_id).lonlat.y).to eq(48.8566)
    expect(Point.where(id: [existing.id, legacy_id]).pluck(:id)).to eq([existing.id])
    expect(user.reload.points_count).to eq(2)
    expect(import.reload.points_count).to eq(2)
  end

  it 'finishes when two legacy-only rows backfill onto the same point in one batch' do
    first_id = connection.select_value(<<~SQL.squish)
      INSERT INTO points (user_id, import_id, timestamp, latitude, longitude, lonlat, created_at, updated_at)
      VALUES (#{user.id}, #{import.id}, #{timestamp}, #{latitude}, #{longitude}, NULL, NOW(), NOW())
      RETURNING id
    SQL
    second_id = connection.select_value(<<~SQL.squish)
      INSERT INTO points (user_id, import_id, timestamp, latitude, longitude, lonlat, created_at, updated_at)
      VALUES (#{user.id}, #{import.id}, #{timestamp}, #{latitude}, #{longitude}, NULL, NOW(), NOW())
      RETURNING id
    SQL

    user.update_column(:points_count, 2)
    import.update_column(:points_count, 2)

    expect { DropLegacyLatLonFromPoints.new.up }.not_to raise_error
    expect(Point.where(id: [first_id, second_id]).pluck(:id)).to eq([first_id])
    expect(Point.find(first_id).lonlat.x).to eq(longitude)
    expect(Point.find(first_id).lonlat.y).to eq(latitude)
    expect(user.reload.points_count).to eq(1)
    expect(import.reload.points_count).to eq(1)
  end

  it 'keeps legacy rows with a missing user or timestamp that the unique index would accept' do
    ids = [
      [user.id, 'NULL'], [user.id, 'NULL'],
      ['NULL', timestamp], ['NULL', timestamp]
    ].map do |user_id, ts|
      connection.select_value(<<~SQL.squish)
        INSERT INTO points (user_id, timestamp, latitude, longitude, lonlat, created_at, updated_at)
        VALUES (#{user_id}, #{ts}, #{latitude}, #{longitude}, NULL, NOW(), NOW())
        RETURNING id
      SQL
    end

    expect { DropLegacyLatLonFromPoints.new.up }.not_to raise_error
    expect(Point.where(id: ids).where.not(lonlat: nil).pluck(:id)).to match_array(ids)
  end
end
