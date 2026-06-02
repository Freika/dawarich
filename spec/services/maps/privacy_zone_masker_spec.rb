# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Maps::PrivacyZoneMasker do
  let(:user) { create(:user) }

  def make_zone(lat:, lon:, radius: 1000)
    tag = create(:tag, :privacy_zone, user: user, privacy_radius_meters: radius)
    place = create(:place, user: user, latitude: lat, longitude: lon)
    create(:tagging, tag: tag, taggable: place)
    tag
  end

  describe '#any?' do
    it 'is false when the user has no privacy zones' do
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

      result = described_class.new(user).mask_points(user.points)

      expect(result).to include(inside)
    end

    it 'excludes points inside a zone and keeps points outside' do
      make_zone(lat: 52.444, lon: 13.500, radius: 1000)
      inside = create(:point, user: user, lonlat: 'POINT(13.500 52.444)')
      outside = create(:point, user: user, lonlat: 'POINT(13.700 52.600)')

      result = described_class.new(user).mask_points(user.points)

      expect(result).to include(outside)
      expect(result).not_to include(inside)
    end

    it 'excludes a point inside any of several zones' do
      make_zone(lat: 52.444, lon: 13.500, radius: 1000)
      make_zone(lat: 48.137, lon: 11.575, radius: 1000)
      berlin = create(:point, user: user, lonlat: 'POINT(13.500 52.444)')
      munich = create(:point, user: user, lonlat: 'POINT(11.575 48.137)')
      elsewhere = create(:point, user: user, lonlat: 'POINT(2.349 48.853)')

      result = described_class.new(user).mask_points(user.points)

      expect(result).to contain_exactly(elsewhere)
      expect(result).not_to include(berlin, munich)
    end
  end

  describe '#mask_places' do
    it 'excludes the zone-defining place itself and keeps places outside' do
      make_zone(lat: 52.444, lon: 13.500, radius: 1000)
      far = create(:place, user: user, latitude: 52.600, longitude: 13.700)

      result = described_class.new(user).mask_places(user.places)

      expect(result).to include(far)
      expect(result.map { |p| [p.latitude.to_f, p.longitude.to_f] })
        .not_to include([52.444, 13.500])
    end
  end

  describe '#in_zone_place_ids' do
    it 'returns ids of places inside any zone' do
      tag = make_zone(lat: 52.444, lon: 13.500, radius: 1000)
      center = tag.places.first
      far = create(:place, user: user, latitude: 52.600, longitude: 13.700)

      ids = described_class.new(user).in_zone_place_ids

      expect(ids).to include(center.id)
      expect(ids).not_to include(far.id)
    end

    it 'is empty when there are no zones' do
      create(:place, user: user, latitude: 52.444, longitude: 13.500)

      expect(described_class.new(user).in_zone_place_ids).to be_empty
    end
  end

  describe '#in_zone?' do
    it 'is true for a coordinate inside a zone, false outside' do
      make_zone(lat: 52.444, lon: 13.500, radius: 1000)
      masker = described_class.new(user)

      expect(masker.in_zone?(13.500, 52.444)).to be(true)
      expect(masker.in_zone?(13.700, 52.600)).to be(false)
    end

    it 'is always false when there are no zones' do
      expect(described_class.new(user).in_zone?(13.500, 52.444)).to be(false)
    end
  end

  describe '#mask_track_geojson' do
    let(:masker) do
      make_zone(lat: 52.444, lon: 13.500, radius: 1000)
      described_class.new(user)
    end

    def feature_collection(coords)
      {
        'type' => 'FeatureCollection',
        'features' => [
          {
            'type' => 'Feature',
            'geometry' => { 'type' => 'LineString', 'coordinates' => coords },
            'properties' => { 'id' => 1 }
          }
        ]
      }
    end

    it 'breaks a line that passes through a zone into two features' do
      coords = [
        [13.300, 52.444], [13.350, 52.444],
        [13.500, 52.444],
        [13.650, 52.444], [13.700, 52.444]
      ]

      result = masker.mask_track_geojson(feature_collection(coords))

      coordinate_sets = result['features'].map { |f| f['geometry']['coordinates'] }
      expect(coordinate_sets).to contain_exactly(
        [[13.300, 52.444], [13.350, 52.444]],
        [[13.650, 52.444], [13.700, 52.444]]
      )
    end

    it 'drops a feature entirely when every vertex is in a zone' do
      coords = [[13.500, 52.444], [13.5005, 52.4441]]

      result = masker.mask_track_geojson(feature_collection(coords))

      expect(result['features']).to be_empty
    end

    it 'returns the collection untouched when there are no zones' do
      no_zone_masker = described_class.new(create(:user))
      fc = feature_collection([[13.300, 52.444], [13.700, 52.444]])

      expect(no_zone_masker.mask_track_geojson(fc)).to eq(fc)
    end
  end
end
