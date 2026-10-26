# frozen_string_literal: true

require 'rails_helper'
require 'tempfile'

RSpec.describe 'Countries flown over in KML imports' do
  let(:user) { create(:user) }
  let(:import) { create(:import, user:, name: 'synthetic-flight.kml', source: 'kml') }
  let(:start_time) { Time.utc(2024, 1, 15) }
  # Invented stops in the open South Pacific, with synthetic geocoding below.
  # The moving legs cover roughly 157 km per ten minutes (about 940 km/h).
  let(:samples) do
    [
      [0, -142, 0, 'Departureland'],
      [60, -142, 0, 'Departureland'],
      [70, -140, 10_000, 'Overflownland'],
      [80, -138, 10_000, 'Overflownland'],
      [90, -136, 0, 'Arrivalland'],
      [150, -136, 0, 'Arrivalland'],
      [210, -136, 0, 'Arrivalland']
    ]
  end

  def time_at(minute)
    (start_time + minute.minutes).iso8601
  end

  def import_kml(body)
    kml = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <kml xmlns="http://www.opengis.net/kml/2.2" xmlns:gx="http://www.google.com/kml/ext/2.2">
        <Document>#{body}</Document>
      </kml>
    XML

    Tempfile.create(['synthetic-flight', '.kml'], Rails.root.join('tmp')) do |file|
      file.write(kml)
      file.flush
      expect { Kml::Importer.new(import, user.id, file.path).call }.to change { user.points.count }.by(samples.size)
    end
  end

  def geocode_samples
    user.points.order(:timestamp).to_a.zip(samples).each do |point, (_, _, _, country)|
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
      # Recalculate an existing month as well as creating it initially.
      2.times { Stats::CalculateMonth.new(user.id, 2024, 1).call }
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

  context 'with a gx:Track without recorded speed' do
    before do
      timestamps = samples.map { |minute, *| "<when>#{time_at(minute)}</when>" }.join
      coordinates = samples.map { |_, longitude, altitude, *| "<gx:coord>#{longitude} -45 #{altitude}</gx:coord>" }.join
      import_kml("<Placemark><name>Synthetic flight</name><gx:Track>#{timestamps}#{coordinates}</gx:Track></Placemark>")
    end

    it_behaves_like 'excludes the overflown country'
  end

  context 'with timestamped Route points whose speed is only in the description' do
    before do
      placemarks = samples.map do |minute, longitude, altitude, *|
        <<~XML
          <Placemark>
            <name>#{time_at(minute)}</name>
            <description><![CDATA[Speed: 507 kt]]></description>
            <TimeStamp><when>#{time_at(minute)}</when></TimeStamp>
            <Point><coordinates>#{longitude},-45,#{altitude}</coordinates></Point>
          </Placemark>
        XML
      end
      import_kml("<Folder><name>Route</name>#{placemarks.join}</Folder>")
    end

    it_behaves_like 'excludes the overflown country'
  end

  context 'with a single fix after a long gap without recorded speed' do
    let(:samples) do
      [
        [0, -142, 0, 'Departureland'],
        [180, -118, 0, 'Arrivalland'],
        [1620, -118.01, 0, 'Returnland']
      ]
    end

    before do
      timestamps = samples.map { |minute, *| "<when>#{time_at(minute)}</when>" }.join
      coordinates = samples.map { |_, longitude, altitude, *| "<gx:coord>#{longitude} -45 #{altitude}</gx:coord>" }.join
      import_kml("<Placemark><name>Sparse trip</name><gx:Track>#{timestamps}#{coordinates}</gx:Track></Placemark>")
      geocode_samples
    end

    it 'keeps the country of the fix that arrived across the gap' do
      trip = create(:trip, user:, started_at: start_time, ended_at: start_time + 2.days,
                           skip_calculation_enqueue: true)

      trip.calculate_countries

      expect(trip.visited_countries).to contain_exactly('Departureland', 'Arrivalland', 'Returnland')
    end
  end

  context 'with a recorded speed of zero' do
    before do
      placemarks = samples.map do |minute, longitude, altitude, *|
        <<~XML
          <Placemark>
            <ExtendedData><Data name="speed"><value>0</value></Data></ExtendedData>
            <TimeStamp><when>#{time_at(minute)}</when></TimeStamp>
            <Point><coordinates>#{longitude},-45,#{altitude}</coordinates></Point>
          </Placemark>
        XML
      end
      import_kml(placemarks.join)
    end

    it 'keeps the recorded speed' do
      expect(user.points.pluck(:velocity).map(&:to_f)).to all(eq(0.0))
    end
  end

  context 'with two parked devices recorded at the same time in one file' do
    let(:samples) { (0..9).map { |minute| [minute, minute.even? ? -142 : -100, 0, 'Homeland'] } }

    before do
      tracks = samples.partition { |minute, *| minute.even? }.map do |track|
        timestamps = track.map { |minute, *| "<when>#{time_at(minute)}</when>" }.join
        coordinates = track.map { |_, longitude, altitude, *| "<gx:coord>#{longitude} -45 #{altitude}</gx:coord>" }.join
        "<Placemark><gx:Track>#{timestamps}#{coordinates}</gx:Track></Placemark>"
      end
      import_kml(tracks.join)
    end

    it 'does not read the jumps between the devices as a flight' do
      expect(user.points.map { |point| point.velocity.to_f * 3.6 }).to all(be <= 500)
    end
  end

  context 'with a Traccar route whose vertices only share a time range' do
    let(:samples) { [[0, -142, 0, 'Homeland'], [1, -141.85, 0, 'Homeland'], [2, -141.7, 0, 'Homeland']] }

    before do
      coordinates = samples.map { |_, longitude, altitude, *| "#{longitude},-45,#{altitude}" }.join(' ')
      name = "#{start_time.strftime('%Y-%m-%d %H:%M')} - #{(start_time + 2.minutes).strftime('%Y-%m-%d %H:%M')}"
      line = "<LineString><coordinates>#{coordinates}</coordinates></LineString>"
      import_kml("<Placemark><name>#{name}</name>#{line}</Placemark>")
    end

    it 'does not derive speeds from the interpolated times' do
      expect(user.points.pluck(:velocity).map(&:to_f)).to all(eq(0.0))
    end
  end
end
