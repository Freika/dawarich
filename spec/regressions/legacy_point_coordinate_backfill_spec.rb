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
    expect(Point.find_by(id: [existing.id, legacy_id]).lonlat).to eq(existing.lonlat)
    expect(user.reload.points_count).to eq(2)
    expect(import.reload.points_count).to eq(2)
  end
end
