# frozen_string_literal: true

require 'rails_helper'
require 'digest'
require 'json'
require 'zlib'

RSpec.describe 'bundled country PMTiles' do
  let(:archive) { Rails.root.join('public/maps/countries-v1.pmtiles') }

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

  it 'matches the checked-in deterministic build manifest' do
    manifest = JSON.parse(Rails.root.join('public/maps/countries-v1.manifest.json').read)
    source = Rails.root.join('lib/assets/countries.geojson.gz')
    build_script = Rails.root.join('script/build_country_pmtiles.py')
    requirements = Rails.root.join('script/country_pmtiles_requirements.txt')
    source_sha = Zlib::GzipReader.open(source) { |gzip| Digest::SHA256.hexdigest(gzip.read) }

    expect(manifest).to include('source_sha256' => source_sha, 'maxzoom' => 8)
    expect(Digest::SHA256.file(build_script).hexdigest).to eq(manifest.fetch('build_script_sha256'))
    expect(Digest::SHA256.file(requirements).hexdigest).to eq(manifest.fetch('requirements_sha256'))
    expect(Digest::SHA256.file(archive).hexdigest).to eq(manifest.fetch('archive_sha256'))
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
