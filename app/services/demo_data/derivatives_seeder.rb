# frozen_string_literal: true

require 'zlib'

class DemoData::DerivativesSeeder
  FIXTURE = Rails.root.join('lib/assets/demo_derivatives.json.gz').freeze

  BERLIN_TOPONYMS = { 'countries' => ['Germany'],                       'cities' => ['Berlin'] }.freeze
  PRAGUE_MIXED    = { 'countries' => ['Germany', 'Czech Republic'],     'cities' => %w[Berlin Prague] }.freeze

  def initialize(user, anchor, import: nil)
    @user = user
    @anchor = anchor
    @import = import
  end

  def call
    @fixture = Zlib::GzipReader.open(FIXTURE) { |gz| Oj.load(gz.read) }

    tags   = seed_tags(@fixture['tags'])
    places = seed_places(@fixture['places'], tags)
    seed_visits(@fixture['visits'], places)
    seed_trip(@fixture['trip'])
    seed_stats(@fixture['stats_daily'])
    DemoData::TracksSeeder.new(@user, @anchor, import: @import).call(@fixture['tracks'])
  end

  private

  def absolute(offset_seconds)
    Time.zone.at(@anchor.to_i + offset_seconds.to_i)
  end

  def seed_tags(rows)
    rows.index_by { |row| row['key'] }.transform_values do |row|
      tag = @user.tags.find_or_initialize_by(name: row['name'])
      if tag.new_record?
        tag.assign_attributes(icon: row['icon'], color: row['color'])
        tag.demo = true
      end
      tag.save! if tag.changed?
      tag
    end
  end

  def seed_places(rows, tags_by_key)
    rows.index_by { |row| row['key'] }.transform_values do |row|
      place = Place.find_or_initialize_by(
        user_id: @user.id,
        latitude: row['lat'],
        longitude: row['lon'],
        demo: true
      )
      place.assign_attributes(
        name: row['name'],
        note: row['note'],
        geodata: row['geodata'] || {},
        source: :photon
      )
      place.save!
      Array(row['tags']).each do |tag_key|
        tag = tags_by_key.fetch(tag_key)
        place.tags << tag unless place.tags.include?(tag)
      end
      place
    end
  end

  def seed_visits(rows, places_by_key)
    rows.each do |row|
      place = places_by_key.fetch(row['place_key'])
      starts = absolute(row['starts_offset_seconds'])
      ends   = absolute(row['ends_offset_seconds'])

      visit = @user.visits.create!(
        name: row['name'] || place.name,
        place: place,
        started_at: starts,
        ended_at: ends,
        duration: ((ends - starts) / 60).to_i,
        status: row['status'].to_sym,
        demo: true
      )

      Array(row['alternates']).each do |alt_key|
        PlaceVisit.find_or_create_by!(visit: visit, place: places_by_key.fetch(alt_key))
      end
    end
  end

  def seed_trip(row)
    return if row.blank?

    trip = @user.trips.new(
      name: row['name'],
      started_at: absolute(row['starts_offset_seconds']),
      ended_at:   absolute(row['ends_offset_seconds']),
      distance: row['distance_meters'],
      demo: true
    )
    trip.description = row['notes'] if row['notes'].present?
    trip.save!
    trip
  end

  def seed_stats(rows)
    return if rows.blank?

    buckets = Hash.new { |h, k| h[k] = { days: [], prague: false } }

    rows.each do |row|
      date = @anchor.to_date + row['day_offset'].to_i
      bucket = buckets[[date.year, date.month]]
      bucket[:days] << [date.day, row['distance_meters'].to_i]
      bucket[:prague] = true if row['in_prague']
    end

    buckets.each do |(year, month), data|
      next if @user.stats.exists?(year: year, month: month)

      toponyms = data[:prague] ? PRAGUE_MIXED : BERLIN_TOPONYMS

      @user.stats.create!(
        year: year,
        month: month,
        distance: data[:days].sum { |_, d| d },
        toponyms: toponyms,
        daily_distance: data[:days].sort_by(&:first)
      )
    end
  end
end
