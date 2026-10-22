# frozen_string_literal: true

require 'rails_helper'
require 'digest'
require 'json'
require 'zlib'

RSpec.describe 'bundled country PMTiles' do
  let(:archive) { Rails.root.join('public/maps/countries-v3.pmtiles') }

  it 'is a PMTiles v3 archive within the accepted eight MiB budget' do
    header = File.binread(archive, 127)

    expect(header.first(8)).to eq("PMTiles\x03")
    expect(header.getbyte(101)).to eq(8)
    expect(File.size(archive)).to be <= 8.megabytes
  end

  it 'keeps total bundled boundary data below the former raw GeoJSON size' do
    compressed_source = Rails.root.join('lib/assets/countries.geojson.gz')

    expect(File.size(archive) + File.size(compressed_source)).to be < 14_643_638
  end

  it 'matches the checked-in asset manifest' do
    manifest = JSON.parse(Rails.root.join('public/maps/countries-v3.manifest.json').read)
    source = Rails.root.join('lib/assets/countries.geojson.gz')
    source_sha = Zlib::GzipReader.open(source) { |gzip| Digest::SHA256.hexdigest(gzip.read) }

    expect(manifest).to include('source_sha256' => source_sha, 'maxzoom' => 8)
    expect(Digest::SHA256.file(archive).hexdigest).to eq(manifest.fetch('archive_sha256'))
  end

  it 'files sampled points under the same country as their ISO 3166-2 subdivision' do
    countries = Zlib::GzipReader.open(Rails.root.join('lib/assets/countries.geojson.gz'), &:read)
    subdivisions = Rails.root.join('lib/assets/admin1_world.geojson').read
    sql = <<~SQL
      SELECT feature -> 'properties' ->> ?
      FROM jsonb_array_elements(?::jsonb -> 'features') AS feature
      WHERE ST_Covers(ST_SetSRID(ST_GeomFromGeoJSON(feature ->> 'geometry'), 4326),
                      ST_SetSRID(ST_MakePoint(?, ?), 4326))
    SQL
    covering = lambda do |geojson, property, longitude, latitude|
      query = ActiveRecord::Base.sanitize_sql_array([sql, property, geojson, longitude, latitude])
      ActiveRecord::Base.connection.select_values(query)
    end

    [[34.10, 44.95], [33.50, 44.58], [13.40, 52.52], [2.17, 41.39]].each do |longitude, latitude|
      subdivision = covering.call(subdivisions, 'iso_3166_2', longitude, latitude)

      expect(subdivision.size).to eq(1)
      expect(covering.call(countries, 'ISO3166-1-Alpha-2', longitude, latitude))
        .to eq([subdivision.first.split('-').first])
    end
  end

  it 'keeps both antimeridian fragments under one canonical country identifier' do
    source = Rails.root.join('lib/assets/countries.geojson.gz')
    document = Zlib::GzipReader.open(source) { |gzip| JSON.parse(gzip.read) }
    fiji = document.fetch('features').find do |feature|
      feature.dig('properties', 'ISO3166-1-Alpha-3') == 'FJI'
    end
    longitudes = fiji.fetch('geometry').fetch('coordinates').flatten
                     .select { |value| value.is_a?(Numeric) }

    expect(fiji.dig('properties', 'ISO3166-1-Alpha-3')).to eq('FJI')
    expect(longitudes).to include(a_value < -179, a_value > 179)
  end
end
