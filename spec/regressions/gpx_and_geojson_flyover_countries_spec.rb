# frozen_string_literal: true

require 'rails_helper'
require 'tempfile'

RSpec.describe 'Countries flown over in GPX and GeoJSON imports' do
  let(:user) { create(:user) }
  let(:start_time) { Time.utc(2024, 1, 15) }
  # Invented stops in the open South Pacific, with synthetic geocoding below.
  # The moving legs cover roughly 157 km per ten minutes (about 940 km/h).
  let(:samples) do
    [
      [0, -142, 'Departureland'],
      [60, -142, 'Departureland'],
      [70, -140, 'Overflownland'],
      [80, -138, 'Overflownland'],
      [90, -136, 'Arrivalland'],
      [150, -136, 'Arrivalland'],
      [210, -136, 'Arrivalland']
    ]
  end

  def time_at(minute)
    (start_time + minute.minutes).iso8601
  end

  def import_file(importer, source, body)
    import = create(:import, user:, name: "synthetic-flight.#{source}", source:, skip_background_processing: true)

    Tempfile.create(['synthetic-flight', ".#{source}"], Rails.root.join('tmp')) do |file|
      file.write(body)
      file.flush
      importer.new(import, user.id, file.path).call
    end
  end

  def gpx(tracks)
    segments = tracks.map do |fixes|
      points = fixes.map do |minute, longitude, *|
        "<trkpt lat=\"-45\" lon=\"#{longitude}\"><ele>0</ele><time>#{time_at(minute)}</time></trkpt>"
      end
      "<trk><trkseg>#{points.join}</trkseg></trk>"
    end
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <gpx version="1.1" creator="spec" xmlns="http://www.topografix.com/GPX/1/1">#{segments.join}</gpx>
    XML
  end

  def geojson(properties = {})
    features = samples.map do |minute, longitude, *|
      { type: 'Feature', geometry: { type: 'Point', coordinates: [longitude, -45] },
        properties: { timestamp: time_at(minute) }.merge(properties) }
    end
    { type: 'FeatureCollection', features: }.to_json
  end

  def geocode_samples
    user.points.order(:timestamp).to_a.zip(samples).each do |point, (_, _, country)|
      point.update_columns(country_name: country, country_id: nil, city: "#{country} City",
                           reverse_geocoded_at: Time.current)
    end
  end

  shared_examples 'excludes the overflown country' do
    before { geocode_samples }

    it 'stores an airborne speed on the moving legs' do
      airborne = user.points.where(country_name: 'Overflownland')

      expect(airborne.map { |point| point.velocity.to_f * 3.6 }).to all(be > 500)
    end

    it 'excludes the flyover from monthly statistics' do
      Stats::CalculateMonth.new(user.id, 2024, 1).call
      countries = user.stats.find_by!(year: 2024, month: 1).toponyms.map { |entry| entry.fetch('country') }

      expect(countries).to contain_exactly('Departureland', 'Arrivalland')
    end

    it 'excludes the flyover from trip countries' do
      trip = create(:trip, user:, started_at: start_time, ended_at: start_time + 4.hours,
                           skip_calculation_enqueue: true)

      trip.calculate_countries

      expect(trip.visited_countries).to contain_exactly('Departureland', 'Arrivalland')
    end
  end

  context 'with a GPX track without speed' do
    before { import_file(Gpx::TrackImporter, 'gpx', gpx([samples])) }

    it_behaves_like 'excludes the overflown country'
  end

  context 'with GeoJSON points without speed' do
    before { import_file(Geojson::Importer, 'geojson', geojson) }

    it_behaves_like 'excludes the overflown country'
  end

  context 'with GeoJSON points that recorded a speed of zero' do
    before { import_file(Geojson::Importer, 'geojson', geojson(speed: 0)) }

    it 'keeps the recorded speed' do
      expect(user.points.pluck(:velocity).map(&:to_f)).to all(eq(0.0))
    end
  end

  context 'with two GPX tracks recorded a kilometre apart at the same time' do
    let(:samples) { (0..11).map { |step| [Rational(step, 12), step.even? ? -142 : -141.987, 'Homeland'] } }

    before { import_file(Gpx::TrackImporter, 'gpx', gpx(samples.partition { |minute, *| (minute * 12).to_i.even? })) }

    it 'does not read the jumps between the tracks as a flight' do
      expect(user.points.map { |point| point.velocity.to_f * 3.6 }).to all(be <= 500)
    end
  end
end
