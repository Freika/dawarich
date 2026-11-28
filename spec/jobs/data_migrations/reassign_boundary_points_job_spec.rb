# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::ReassignBoundaryPointsJob, type: :job do
  let(:user) { create(:user) }

  def bundled_country(iso_a2)
    path = Rails.root.join('lib/assets/countries.geojson.gz')
    @bundled ||= Zlib::GzipReader.open(path) { |gzip| JSON.parse(gzip.read) }
    feature = @bundled['features'].find { |f| f.dig('properties', 'ISO3166-1-Alpha-2') == iso_a2 }
    geometry = RGeo::GeoJSON.decode(feature['geometry'].to_json, geo_factory: RGeo::Geos.factory(srid: 4326))

    create(:country, name: feature.dig('properties', 'name'), iso_a2: iso_a2,
                     iso_a3: feature.dig('properties', 'ISO3166-1-Alpha-3'), geom: geometry)
  end

  let!(:target) { bundled_country(described_class::TARGET_CODE) }
  let!(:source) { bundled_country(described_class::SOURCE_CODE) }

  # Written with update_columns so the after_create spatial lookup can't decide
  # the country: these rows model points resolved before the source changed.
  def point_at(lon, lat, country:, timestamp: 1_700_000_000)
    create(:point, user: user, lonlat: "POINT(#{lon} #{lat})", timestamp: timestamp)
      .tap { |point| point.update_columns(country_id: country&.id) }
  end

  it 'moves points to the country whose reloaded polygon covers them' do
    first = point_at(34.10, 44.95, country: source)
    second = point_at(33.50, 44.58, country: source, timestamp: 1_700_000_100)

    described_class.perform_now

    expect(first.reload.country_id).to eq(target.id)
    expect(second.reload.country_id).to eq(target.id)
  end

  it 'relabels moved points still carrying the previous country label and keeps other provider labels' do
    labelled = point_at(34.10, 44.95, country: source)
    labelled.update_columns(country_name: source.name, country: source.name)
    unlabelled = point_at(33.50, 44.58, country: source, timestamp: 1_700_000_100)
    unlabelled.update_columns(country_name: nil, country: nil)
    provider = point_at(34.20, 45.00, country: source, timestamp: 1_700_000_200)
    provider.update_columns(country_name: 'Provider label')

    described_class.perform_now

    expect([labelled.reload.country_name, labelled[:country]]).to eq([target.name, target.name])
    expect([unlabelled.reload.country_name, unlabelled[:country]]).to eq([target.name, target.name])
    expect(provider.reload.country_name).to eq('Provider label')
  end

  it 'leaves points outside the target polygon alone, including the shore across the strait' do
    elsewhere = point_at(37.62, 55.75, country: source)
    across_strait = point_at(36.80, 45.25, country: source, timestamp: 1_700_000_100)

    described_class.perform_now

    expect(elsewhere.reload.country_id).to eq(source.id)
    expect(across_strait.reload.country_id).to eq(source.id)
  end

  it 'decides by the target polygon, not the bounding box' do
    offshore = point_at(36.0, 44.5, country: source)
    expect(Country.containing_point(36.0, 44.5)).to be_nil

    described_class.perform_now

    expect(offshore.reload.country_id).to eq(source.id)
  end

  it 'leaves unresolved points for the regular country backfill' do
    unresolved = point_at(34.10, 44.95, country: nil)

    described_class.perform_now

    expect(unresolved.reload.country_id).to be_nil
  end

  it 'rechecks achievements for users whose points moved' do
    point_at(34.10, 44.95, country: source)
    other = create(:user)
    clear_achievement_checks(user.id)
    create(:point, user: other, lonlat: 'POINT(37.62 55.75)').update_columns(country_id: source.id)

    described_class.perform_now

    expect(Achievements::CheckJob).to have_been_enqueued.with(user.id)
    expect(Achievements::CheckJob).not_to have_been_enqueued.with(other.id)
  end

  it 'queues the moved days for a toponym refresh' do
    point_at(34.10, 44.95, country: source, timestamp: Time.utc(2025, 6, 1, 12).to_i)
    clear_geocoded_days

    described_class.perform_now

    pending = Sidekiq.redis { |redis| redis.zrange(Stats::GeocodedDays::PENDING_KEY, 0, -1) }
    expect(pending).to include("#{user.id}:2025-06-01")
  end

  it 'does nothing when either country is missing' do
    unmoved = point_at(34.10, 44.95, country: source)
    target.destroy!

    expect { described_class.perform_now }.not_to raise_error
    expect(unmoved.reload.country_id).to eq(source.id)
  end
end
