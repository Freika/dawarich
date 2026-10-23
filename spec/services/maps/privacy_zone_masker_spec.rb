# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Maps::PrivacyZoneMasker do
  let(:user) { create(:user) }

  def make_zone(lat:, lon:, radius: 1000, owner: user)
    tag = create(:tag, :privacy_zone, user: owner, privacy_radius_meters: radius)
    place = create(:place, user: owner, latitude: lat, longitude: lon, lonlat: "POINT(#{lon} #{lat})")
    create(:tagging, tag: tag, taggable: place)
    tag
  end

  def sql_value(sql)
    ActiveRecord::Base.connection.select_value(sql)
  end

  def line(*coords)
    "ST_GeomFromText('LINESTRING(#{coords.map { |c| c.join(' ') }.join(', ')})', 4326)"
  end

  describe '#any?' do
    it 'is false when the user has no privacy zones' do
      expect(described_class.new(user).any?).to be(false)
    end

    it 'is false for a zone tag without places' do
      create(:tag, :privacy_zone, user: user)

      expect(described_class.new(user).any?).to be(false)
    end

    it 'is true when the user has a privacy zone with a place' do
      make_zone(lat: 52.444, lon: 13.500)

      expect(described_class.new(user).any?).to be(true)
    end
  end

  describe '#mask_points' do
    it 'returns the relation untouched when there are no zones' do
      inside = create(:point, user: user, lonlat: 'POINT(13.500 52.444)')

      expect(described_class.new(user).mask_points(user.points)).to include(inside)
    end

    it 'excludes points inside a zone and keeps points outside' do
      make_zone(lat: 52.444, lon: 13.500)
      inside = create(:point, user: user, lonlat: 'POINT(13.500 52.444)')
      outside = create(:point, user: user, lonlat: 'POINT(13.700 52.600)')

      result = described_class.new(user).mask_points(user.points)

      expect(result).to include(outside)
      expect(result).not_to include(inside)
    end

    it 'excludes a point inside any of several overlapping or separate zones' do
      make_zone(lat: 52.444, lon: 13.500)
      make_zone(lat: 52.445, lon: 13.501)
      make_zone(lat: 48.137, lon: 11.575)
      berlin = create(:point, user: user, lonlat: 'POINT(13.500 52.444)')
      munich = create(:point, user: user, lonlat: 'POINT(11.575 48.137)')
      elsewhere = create(:point, user: user, lonlat: 'POINT(2.349 48.853)')

      expect(described_class.new(user).mask_points(user.points)).to contain_exactly(elsewhere)
      expect(user.points).to include(berlin, munich)
    end

    it 'ignores zones of other users' do
      make_zone(lat: 52.444, lon: 13.500, owner: create(:user))
      inside = create(:point, user: user, lonlat: 'POINT(13.500 52.444)')

      expect(described_class.new(user).mask_points(user.points)).to include(inside)
    end
  end

  describe '#mask_places' do
    it 'excludes the zone-defining place and keeps places outside' do
      tag = make_zone(lat: 52.444, lon: 13.500)
      far = create(:place, user: user, latitude: 52.600, longitude: 13.700, lonlat: 'POINT(13.700 52.600)')

      result = described_class.new(user).mask_places(user.places)

      expect(result).to include(far)
      expect(result).not_to include(tag.places.first)
    end
  end

  describe '#in_zone_place_ids' do
    it 'returns ids of places inside any zone' do
      tag = make_zone(lat: 52.444, lon: 13.500)
      far = create(:place, user: user, latitude: 52.600, longitude: 13.700, lonlat: 'POINT(13.700 52.600)')

      ids = described_class.new(user).in_zone_place_ids

      expect(ids).to include(tag.places.first.id)
      expect(ids).not_to include(far.id)
    end

    it 'is empty when there are no zones' do
      create(:place, user: user, latitude: 52.444, longitude: 13.500, lonlat: 'POINT(13.500 52.444)')

      expect(described_class.new(user).in_zone_place_ids).to be_empty
    end
  end

  describe '#in_zone?' do
    it 'is true for a coordinate inside a zone, false outside, false without zones' do
      expect(described_class.new(user).in_zone?(13.500, 52.444)).to be(false)

      make_zone(lat: 52.444, lon: 13.500)
      masker = described_class.new(user)

      expect(masker.in_zone?(13.500, 52.444)).to be(true)
      expect(masker.in_zone?(13.700, 52.600)).to be(false)
    end

    it 'agrees with the SQL predicate on both sides of the boundary' do
      make_zone(lat: 52.444, lon: 13.500, radius: 1000)
      masker = described_class.new(user)
      lat_per_meter = 1.0 / 111_194.93

      [999.7, 1000.3].each do |meters|
        lat = 52.444 + (meters * lat_per_meter)
        sql = masker.within_sql("ST_SetSRID(ST_MakePoint(13.5, #{lat}), 4326)::geography")

        expect(sql_value("SELECT #{sql}")).to eq(masker.in_zone?(13.5, lat))
      end
    end
  end

  describe '#within_sql and #touches_sql' do
    it 'returns FALSE without zones so it can be OR-ed into any query' do
      masker = described_class.new(user)

      expect(masker.within_sql('points.lonlat')).to eq('FALSE')
      expect(masker.touches_sql('tracks.original_path')).to eq('FALSE')
    end

    it 'detects a line that crosses a zone without a vertex inside it' do
      make_zone(lat: 52.444, lon: 13.500, radius: 500)
      masker = described_class.new(user)

      crossing = line([13.40, 52.444], [13.60, 52.444])
      clear = line([13.40, 52.500], [13.60, 52.500])

      expect(sql_value("SELECT #{masker.touches_sql(crossing)}")).to be(true)
      expect(sql_value("SELECT #{masker.touches_sql(clear)}")).to be(false)
    end
  end

  describe '#clip_sql' do
    it 'returns the geometry unchanged without zones' do
      expect(described_class.new(user).clip_sql('tracks.original_path')).to eq('tracks.original_path')
    end

    it 'cuts a crossing line into two pieces with nothing left inside the zone' do
      make_zone(lat: 52.444, lon: 13.500, radius: 500)
      masker = described_class.new(user)
      clipped = masker.clip_sql(line([13.40, 52.444], [13.60, 52.444]))
      center = 'ST_SetSRID(ST_MakePoint(13.5, 52.444), 4326)::geography'

      expect(sql_value("SELECT ST_NumGeometries(#{clipped})")).to eq(2)
      expect(sql_value("SELECT ST_Distance((#{clipped})::geography, #{center}, false)")).to be >= 500
    end

    it 'leaves a line far from the zone untouched' do
      make_zone(lat: 52.444, lon: 13.500, radius: 500)
      clipped = described_class.new(user).clip_sql(line([13.40, 52.600], [13.60, 52.600]))

      expect(sql_value("SELECT ST_Equals(#{clipped}, #{line([13.40, 52.600], [13.60, 52.600])})")).to be(true)
    end

    it 'leaves nothing of a line entirely inside the zone' do
      make_zone(lat: 52.444, lon: 13.500, radius: 500)
      clipped = described_class.new(user).clip_sql(line([13.4995, 52.444], [13.5005, 52.444]))

      expect(sql_value("SELECT ST_IsEmpty(#{clipped})")).to be(true)
    end
  end

  describe '#fingerprint' do
    it 'is nil without zones and changes when a radius changes' do
      expect(described_class.new(user).fingerprint).to be_nil

      tag = make_zone(lat: 52.444, lon: 13.500, radius: 500)
      before = described_class.new(user).fingerprint
      tag.update!(privacy_radius_meters: 600)

      expect(before).to be_present
      expect(described_class.new(user).fingerprint).not_to eq(before)
    end
  end

  describe '#near' do
    it 'keeps only zones whose circle can reach the bounding box' do
      make_zone(lat: 52.444, lon: 13.500, radius: 500)
      make_zone(lat: 48.137, lon: 11.575, radius: 500)
      masker = described_class.new(user)

      near_berlin = masker.near(min_lon: 13.49, min_lat: 52.44, max_lon: 13.51, max_lat: 52.45)
      far_away = masker.near(min_lon: 2.30, min_lat: 48.80, max_lon: 2.40, max_lat: 48.90)

      expect(near_berlin.any?).to be(true)
      expect(near_berlin.in_zone?(11.575, 48.137)).to be(false)
      expect(far_away.any?).to be(false)
      expect(far_away.within_sql('points.lonlat')).to eq('FALSE')
    end
  end

  describe '#covers_bbox?' do
    it 'is true only when the whole box lies inside one zone' do
      make_zone(lat: 52.444, lon: 13.500, radius: 1000)
      masker = described_class.new(user)

      expect(masker.covers_bbox?(min_lon: 13.4995, min_lat: 52.4437, max_lon: 13.5005, max_lat: 52.4443)).to be(true)
      expect(masker.covers_bbox?(min_lon: 13.48, min_lat: 52.43, max_lon: 13.52, max_lat: 52.46)).to be(false)
      expect(described_class.new(create(:user)).covers_bbox?(min_lon: 0, min_lat: 0, max_lon: 1,
                                                             max_lat: 1)).to be(false)
    end
  end
end
