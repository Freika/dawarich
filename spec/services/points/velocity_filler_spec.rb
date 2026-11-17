# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::VelocityFiller do
  let(:user) { create(:user) }
  let(:start_time) { Time.utc(2024, 1, 15).to_i }
  # Invented fixes on the equator, mid-Atlantic. 1 degree of longitude is ~111.2 km on the sphere.
  let(:meters_per_degree) { 111_194.9 }
  let(:cruise_meters_per_fix) { 500 } # every 2 s: 250 m/s, 900 km/h

  def create_fixes(import, offsets_in_meters, seconds_between: 2, velocity: nil)
    offsets_in_meters.each_with_index.map do |meters, index|
      create(:point, user:, import:, velocity:, timestamp: start_time + (index * seconds_between),
                     lonlat: "POINT(#{-30 + (meters / meters_per_degree)} 0)")
    end
  end

  def kmh(point)
    point.reload.velocity&.to_f.to_f * 3.6
  end

  def legacy_adjacent_speed(previous, point, following)
    Point.connection.select_value(Point.sanitize_sql([<<~SQL.squish, previous.id, point.id, following.id]))
      SELECT ROUND(LEAST(ST_Distance(a.lonlat, b.lonlat, false) / (b.timestamp - a.timestamp),
                         ST_Distance(b.lonlat, c.lonlat, false) / (c.timestamp - b.timestamp))::numeric, 1)::text
      FROM points a, points b, points c WHERE a.id = ? AND b.id = ? AND c.id = ?
    SQL
  end

  # Dense in-flight fixes with a stale repeat (index 20) and a forward spike (index 30):
  # adjacent legs read ~0 km/h and ~2000 km/h there.
  def jittery_cruise(import, stale_offset: 19 * 500)
    offsets = (0...40).map { |index| index * cruise_meters_per_fix }
    offsets[20] = stale_offset
    offsets[30] += 600
    create_fixes(import, offsets)
  end

  describe '#call' do
    let(:import) { create(:import, user:, source: 'kml', skip_background_processing: true) }

    it 'reads cruise speed through position jitter on dense fixes' do
      points = jittery_cruise(import)

      described_class.new(import.id).call

      expect(points[1..-2].map { |point| kmh(point) }).to all(be > 500)
    end

    it 'reads glitched fixes mid-flight as flying on sparse fixes' do
      # Every 30 s at 900 km/h; index 10 repeats a stale position, index 20 jumps 12 km ahead.
      offsets = (0...30).map { |index| index * 7_500 }
      offsets[10] = offsets[9]
      offsets[20] += 12_000
      points = create_fixes(import, offsets, seconds_between: 30)

      described_class.new(import.id).call

      expect(points[1..-2].map { |point| kmh(point) }).to all(be > 500)
    end

    it 'keeps the slow fixes of a landing on the ground' do
      # Cruise, then a stop: after the last flying fix nothing moves for ten minutes.
      offsets = (0...10).map { |index| index * 7_500 } + ([9 * 7_500] * 20)
      points = create_fixes(import, offsets, seconds_between: 30)

      described_class.new(import.id).call

      expect(points[10..-2].map { |point| kmh(point) }).to all(be < 1)
    end

    it 'keeps a fix next to a long gap at the slower of its two speeds' do
      # A photo-like sequence: 9 h jump across the ocean, then an hour on foot.
      points = create_fixes(import, [0, 6_670_000, 6_671_000], seconds_between: 9 * 3600)
      points.last.update_columns(timestamp: points[1].timestamp + 3600)

      described_class.new(import.id).call

      expect(kmh(points[1])).to be < 10
    end

    it 'leaves recorded speeds alone' do
      points = jittery_cruise(import)
      points.each { |point| point.update_columns(velocity: '3.0') }

      described_class.new(import.id).call

      expect(points.map { |point| point.reload.velocity }).to all(eq('3.0'))
    end
  end

  describe '#call with upgrade_flyovers' do
    let(:import) { create(:import, user:, source: 'gpx', skip_background_processing: true) }

    it 'upgrades a slow speed the old adjacent-leg formula derived' do
      points = jittery_cruise(import, stale_offset: (19 * 500) + 10)
      derived = legacy_adjacent_speed(*points[19..21])
      points[20].update_columns(velocity: derived)

      described_class.new(import.id, upgrade_flyovers: true).call

      aggregate_failures do
        expect(derived.to_f * 3.6).to be < 500
        expect(kmh(points[20])).to be > 500
      end
    end

    it 'upgrades zero speeds only when told they stand for a missing speed' do
      points = jittery_cruise(import)
      points.each { |point| point.update_columns(velocity: '0') }

      described_class.new(import.id, upgrade_flyovers: true).call
      kept = points.map { |point| kmh(point) }
      described_class.new(import.id, upgrade_flyovers: true, zero_is_missing: true).call

      aggregate_failures do
        expect(kept).to all(be_zero)
        expect(points[1..-2].map { |point| kmh(point) }).to all(be > 500)
      end
    end

    it 'keeps a recorded slow speed the old formula would not have produced' do
      points = jittery_cruise(import, stale_offset: (19 * 500) + 10)
      points[20].update_columns(velocity: '4.0')

      described_class.new(import.id, upgrade_flyovers: true).call

      expect(points[20].reload.velocity).to eq('4.0')
    end

    it 'writes nothing below flight speed' do
      walk = create_fixes(import, [0, 15, 30, 45], seconds_between: 10)

      result = described_class.new(import.id, upgrade_flyovers: true).call

      expect([result.updated, walk.map { |point| point.reload.velocity }.uniq]).to eq([0, [nil]])
    end
  end
end
