# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Point upsert returns a known xmax type' do
  let(:user) { create(:user) }

  def capture_stderr
    original = $stderr
    $stderr = StringIO.new
    yield
    $stderr.string
  ensure
    $stderr = original
  end

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

  it 'does not warn that the type of xmax is unrecognized' do
    warnings = capture_stderr { upsert(1.day.ago.to_i) }

    expect(warnings).not_to include('unknown OID')
    expect(warnings).not_to include('xmax')
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

  it 'is the single definition every ingest path uses' do
    creators = [
      Overland::PointsCreator,
      OwnTracks::PointCreator,
      Traccar::PointCreator
    ]

    creators.each do |creator|
      expect(creator::RETURNING_COLUMNS).to eq(Point::UPSERT_RETURNING_COLUMNS)
    end
  end
end
