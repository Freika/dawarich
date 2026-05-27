# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Imports reject unusable locations' do
  let(:user) { create(:user) }

  def import_gpx(waypoint)
    body = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <gpx version="1.1" creator="test" xmlns="http://www.topografix.com/GPX/1/1">
      #{waypoint}
      </gpx>
    XML
    path = Rails.root.join('tmp', "#{SecureRandom.hex(4)}-waypoints.gpx")
    File.write(path, body)
    import = create(:import, user:, name: File.basename(path), source: 'gpx')
    import.file.attach(Rack::Test::UploadedFile.new(path, 'application/xml'))
    Gpx::TrackImporter.new(import, user.id).call
  ensure
    File.delete(path) if path && File.exist?(path)
  end

  def import_geojson(json)
    path = Rails.root.join('tmp', "#{SecureRandom.hex(4)}-features.json")
    File.write(path, json)
    import = create(:import, user:, name: File.basename(path), source: 'geojson')
    import.file.attach(Rack::Test::UploadedFile.new(path, 'application/json'))
    Geojson::Importer.new(import, user.id).call
  ensure
    File.delete(path) if path && File.exist?(path)
  end

  def feature_collection(*features)
    %({"type":"FeatureCollection","features":[#{features.join(',')}]})
  end

  def point_feature(name, coordinates)
    %({"type":"Feature","properties":{"name":"#{name}"},"geometry":{"type":"Point","coordinates":#{coordinates}}})
  end

  it 'drops a waypoint whose latitude is not a number instead of placing it on the equator' do
    expect { import_gpx('<wpt lat="north" lon="13.404954"><name>Nonsense</name></wpt>') }
      .to raise_error(Imports::NoImportableDataError)
    expect(Place.count).to eq(0)
  end

  it 'drops a waypoint whose coordinates are off the globe' do
    expect { import_gpx('<wpt lat="91.5" lon="13.404954"><name>Off globe</name></wpt>') }
      .to raise_error(Imports::NoImportableDataError)
    expect(Place.count).to eq(0)
  end

  it 'reports a GeoJSON file whose geometries are all unsupported' do
    ring = '[[[13.0,52.0],[13.1,52.0],[13.1,52.1],[13.0,52.0]]]'
    polygon = %({"type":"Feature","properties":{},"geometry":{"type":"Polygon","coordinates":#{ring}}})

    expect { import_geojson(feature_collection(polygon)) }.to raise_error(Imports::NoImportableDataError)
  end

  it 'reports a GeoJSON file whose untimed points all have unusable coordinates' do
    garbage = feature_collection(
      point_feature('off globe', '[13.4,999.0]'),
      point_feature('nonsense', '["east",52.5]')
    )

    expect { import_geojson(garbage) }.to raise_error(Imports::NoImportableDataError)
    expect(Place.count).to eq(0)
  end

  it 'reports a GeoJSON file with no features at all' do
    expect { import_geojson(feature_collection) }.to raise_error(Imports::NoImportableDataError)
  end
end
