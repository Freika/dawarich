# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Point upsert returns a known xmax type' do
  let(:user) { create(:user) }
  let(:xid_oid) { 28 }

  def upsert(timestamp)
    Point.archival_safe_upsert_all(
      [{
        user_id: user.id,
        lonlat: 'POINT(12.3712 51.3402)',
        timestamp: timestamp
      }],
      returning: Arel.sql(Point::UPSERT_RETURNING_COLUMNS)
    )
  end

  # Asserting the wire type rather than the adapter's warning: the adapter
  # registers a String fallback for an unmapped OID the first time it sees it,
  # so a warning-based check passes for free once any earlier example has
  # already triggered it.
  it 'hands the adapter a mapped type instead of the raw xid' do
    connection = ActiveRecord::Base.connection.raw_connection
    result = connection.exec(<<~SQL.squish)
      INSERT INTO points (user_id, lonlat, timestamp, created_at, updated_at)
      VALUES (#{user.id}, ST_GeomFromText('POINT(12.3712 51.3402)', 4326), #{4.days.ago.to_i}, NOW(), NOW())
      RETURNING #{Point::UPSERT_RETURNING_COLUMNS}
    SQL

    xmax_field = result.fields.index('xmax')

    expect(xmax_field).not_to be_nil
    expect(result.ftype(xmax_field)).not_to eq(xid_oid)
  end

  it 'still distinguishes an inserted row from an updated one' do
    timestamp = 2.days.ago.to_i

    inserted = upsert(timestamp)
    updated = upsert(timestamp)

    expect(inserted.count { |row| row['xmax'].to_i.zero? }).to eq(1)
    expect(updated.count { |row| row['xmax'].to_i.zero? }).to eq(0)
  end

  it 'still returns the coordinates and identifiers callers rely on' do
    row = upsert(3.days.ago.to_i).first

    expect(row['id']).to be_present
    expect(row['longitude'].to_f).to be_within(0.0001).of(12.3712)
    expect(row['latitude'].to_f).to be_within(0.0001).of(51.3402)
  end
end
