# frozen_string_literal: true

require 'rails_helper'

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
  end
end
