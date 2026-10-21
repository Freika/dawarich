# frozen_string_literal: true

require 'rails_helper'
require 'tempfile'

RSpec.describe DemoData::PointsSeeder do
  let(:user) { create(:user) }
  let(:import) { create(:import, user: user, demo: true) }
  let(:anchor) { Time.zone.local(2026, 5, 28).beginning_of_day }

  describe '#call' do
    it 'inserts the bundled GeoJSON points scoped to the user and import' do
      described_class.new(user, import, anchor).call
      expect(Point.where(user_id: user.id, import_id: import.id).count).to be > 600
    end

    it 'shifts timestamps so the latest point lands at or just before the anchor day end' do
      described_class.new(user, import, anchor).call
      max_ts = Point.where(user_id: user.id).maximum(:timestamp)
      expect(max_ts).to be <= anchor.to_i + 86_400
      expect(max_ts).to be >= anchor.to_i - 86_400
    end

    it 'sets a valid PostGIS lonlat geometry on every inserted row' do
      described_class.new(user, import, anchor).call
      missing = Point.where(user_id: user.id, lonlat: nil).count
      expect(missing).to eq(0)
    end

    it 'backfills country_id from PostGIS country boundaries' do
      Country.find_or_create_by!(name: 'Germany') do |c|
        c.iso_a2 = 'DE'
        c.iso_a3 = 'DEU'
        c.geom = 'MULTIPOLYGON(((5 47, 16 47, 16 55, 5 55, 5 47)))'
      end

      described_class.new(user, import, anchor).call

      with_country = Point.where(user_id: user.id).where.not(country_id: nil).count
      expect(with_country).to be > 0
    end

    it 'assigns points to both matching countries and leaves unmatched points unset' do
      west = Country.create!(
        name: 'Demo West', iso_a2: 'XW', iso_a3: 'XWW',
        geom: 'MULTIPOLYGON(((-151 -31, -149 -31, -149 -29, -151 -29, -151 -31)))'
      )
      east = Country.create!(
        name: 'Demo East', iso_a2: 'XE', iso_a3: 'XEE',
        geom: 'MULTIPOLYGON(((-121 -31, -119 -31, -119 -29, -121 -29, -121 -31)))'
      )
      fixture = {
        'seed_date' => '2026-05-28T00:00:00Z',
        'features' => [-150, -120, -90].each_with_index.map do |lon, index|
          { 'properties' => { 'latitude' => -30, 'longitude' => lon, 'timestamp' => 1_779_926_400 + index } }
        end
      }

      Tempfile.create(['demo-points', '.json.gz']) do |file|
        Zlib::GzipWriter.open(file.path) { |gz| gz.write(Oj.dump(fixture)) }
        stub_const('DemoData::PointsSeeder::FIXTURE', file.path)

        described_class.new(user, import, anchor).call
      end

      expect(import.points.order(:timestamp).pluck(:country_id)).to eq([west.id, east.id, nil])
    end
  end
end
