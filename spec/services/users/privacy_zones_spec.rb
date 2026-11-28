# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::PrivacyZones do
  let(:user) { create(:user) }
  let(:tag) { create(:tag, user: user, privacy_radius_meters: 300) }

  def zone_place(lat, lon, tag_record = tag)
    create(:place, user: user, latitude: lat, longitude: lon).tap do |place|
      create(:tagging, tag: tag_record, taggable: place)
    end
  end

  def geo_distance(lat1, lon1, lat2, lon2)
    ApplicationRecord.connection.select_value(
      ApplicationRecord.sanitize_sql_array(
        ['SELECT ST_Distance(ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ' \
         'ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography)', lon1, lat1, lon2, lat2]
      )
    ).to_f
  end

  it 'returns an empty array when the user has no privacy zones' do
    expect(described_class.new(user).call).to eq([])
  end

  it 'shifts every circle off its place by 30 to 60 percent of the radius' do
    places = Array.new(20) { zone_place(52.5, 13.4) }

    zones = described_class.new(user).call
    shifts = zones.map { |zone| geo_distance(zone[:lat], zone[:lon], 52.5, 13.4) }

    expect(zones.pluck(:place_id)).to match_array(places.map(&:id))
    expect(shifts).to all(be_between(0.3 * 300 * 0.99, 0.6 * 300 * 1.01))
  end

  it 'keeps the whole radius around the place inside the shifted circle' do
    zone_place(52.5, 13.4)

    zone = described_class.new(user).call.sole
    shift = geo_distance(zone[:lat], zone[:lon], 52.5, 13.4)

    expect(zone[:radius]).to be >= shift + 300
    expect(zone[:radius]).to be <= (shift + 300) * 1.02
  end

  it 'covers the radius near the poles too' do
    zone_place(89.9, 10.0)

    zone = described_class.new(user).call.sole

    expect(zone[:radius]).to be >= geo_distance(zone[:lat], zone[:lon], 89.9, 10.0) + 300
  end

  it 'keeps the longitude in range next to the antimeridian' do
    zone_place(0.0, 179.9999)
    zone_place(0.0, -179.9999)

    expect(described_class.new(user).call.pluck(:lon)).to all(be_between(-180.0, 180.0))
  end

  it 'returns the same circle on every call' do
    zone_place(52.5, 13.4)

    expect(described_class.new(user).call).to eq(described_class.new(user.reload).call)
  end

  it 'shifts each place in its own direction' do
    zone_place(52.5, 13.4)
    zone_place(52.5, 13.4)

    first, second = described_class.new(user).call
    expect([first[:lat], first[:lon]]).not_to eq([second[:lat], second[:lon]])
  end

  it 'shifts the circle in a new direction when the radius changes' do
    zone_place(52.5, 13.4)
    before = described_class.new(user).call.sole

    tag.update!(privacy_radius_meters: 600)
    after = described_class.new(user.reload).call.sole

    bearing = ->(zone) { Math.atan2(zone[:lon] - 13.4, zone[:lat] - 52.5) }
    expect(bearing.call(after)).not_to be_within(0.01).of(bearing.call(before))
  end
end
