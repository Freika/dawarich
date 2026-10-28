# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Observed nature and geographic achievements' do
  let(:user) { create(:user) }
  let(:dataset) { Exploration::Dataset.create!(version: 'observed-test', completed_at: Time.current) }
  let(:base) { Time.utc(2026, 6, 1, 10).to_i }

  before do
    allow(Exploration::Geography).to receive_messages(current: dataset, install!: dataset)
    allow(Achievements::LocationTimezone).to receive(:call).and_return('Europe/Berlin')
    ApplicationRecord.connection.execute(<<~SQL)
      INSERT INTO exploration_territories(dataset_id,code,name,kind,timezone,boundary,land,land_area)
      SELECT #{dataset.id},'park_test','Test Park','park','Europe/Berlin',g,g,ST_Area(g::geography)
      FROM (SELECT ST_Multi(ST_MakeEnvelope(13.30,52.49,13.40,52.55,4326)) g) s
    SQL
  end

  def record(minutes:, at: base, lon: 13.35, lat: 52.51, device: 'phone', anomaly: false)
    Point.insert_all!((0..minutes).map do |minute|
      { user_id: user.id, timestamp: at + minute * 60, lonlat: "POINT(#{lon} #{lat})",
        tracker_id: device, anomaly: anomaly, created_at: Time.current, updated_at: Time.current }
    end)
  end

  def observe(**options)
    Achievements::ObservedTime.new(user, dataset: dataset, **options).call
  end

  it 'requires thirty observed park minutes, unions devices, and records the historic qualifying instant' do
    record(minutes: 20)
    record(minutes: 20, device: 'watch', lon: 13.35001)
    expect(observe.fetch('park_test')['seconds']).to eq(1200)
    record(minutes: 15, at: base + 21 * 60)
    fact = observe.fetch('park_test')
    expect(fact['seconds']).to eq(1800)
    expect(fact['at']).to eq(Time.at(base + 30 * 60).utc.iso8601)
    rows = Achievements::GeographicResults.call(dataset, observe)
    expect(rows.find { |r| r[:series] == 'parks' }[:data]['progress']).to eq(1)
  end

  it 'does not bridge gaps, anomalies, flights or observations outside the park' do
    record(minutes: 5)
    record(minutes: 5, at: base + 60 * 60)
    record(minutes: 20, at: base + 120 * 60, anomaly: true)
    record(minutes: 20, at: base + 180 * 60, lon: 14)
    expect(observe.fetch('park_test')['seconds']).to eq(600)
    user.points.delete_all
    record(minutes: 1)
    record(minutes: 1, at: base + 9 * 60)
    expect(observe.fetch('park_test')['seconds']).to eq(240)
  end

  it 'splits local midnight, excludes private observations and never counts a border cell as a park visit' do
    record(minutes: 20, at: Time.utc(2026, 6, 1, 21, 50).to_i)
    expect(observe.fetch('park_test')['seconds']).to eq(600)
    masker = Maps::PrivacyZoneMasker.new(user,
                                         circles: [Maps::PrivacyZoneMasker::Circle.new(lon: 13.35, lat: 52.51,
                                                                                       radius: 1000)])
    expect(observe(privacy_zone_masker: masker)).to be_empty
    user.points.delete_all
    record(minutes: 40, lon: 13.40001)
    expect(observe).not_to have_key('park_test')
  end

  it 'requires each quadrant independently and excludes ten-kilometre margins at both meridians and the equator' do
    expect(Achievements::GeographicRegions.memberships(1, 179.999)).to eq(['north'])
    expect(Achievements::GeographicRegions.memberships(-1, -179.999)).to eq(['south'])
    expect(Achievements::GeographicRegions.memberships(0.001, 0.001)).to be_empty
    expect(Achievements::GeographicRegions.memberships(66.57, 20)).not_to include('arctic')
    expect(Achievements::GeographicRegions.memberships(67, 20)).to include('arctic')
    record(minutes: 10, lat: 50, lon: 13)
    record(minutes: 10, at: base + 3600, lat: -50, lon: -13)
    rows = Achievements::GeographicResults.call(dataset, observe)
    expect(rows.find { |r| r[:subject_key] == 'north_south' }[:data]['levels']).to have_key('1')
    expect(rows.find { |r| r[:subject_key] == 'east_west' }[:data]['levels']).to have_key('1')
    expect(rows.find { |r| r[:subject_key] == 'four_quarters' }[:data]['levels']).to be_empty
  end

  it 'revokes new awards after bulk deletion and keeps a separate masked public projection' do
    record(minutes: 30)
    Achievements::CollectionChecker.new(user, notify: false).call
    card = user.achievement_collectibles.find_by!(series: 'park')
    expect(card.level).to eq(1)
    expect(card.publishable?).to be(true)
    place = create(:place, user: user, latitude: 52.51, longitude: 13.35)
    place.tags << create(:tag, user: user, privacy_radius_meters: 1000)
    expect(card.publishable?).to be(false)
    Achievements::CollectionChecker.new(user, notify: false).call
    expect(card.reload.level).to eq(1)
    expect(Achievements::CollectiblePresenter.new(card, public: true).card.level).to eq(0)
    user.points.delete_all
    Achievements::CollectionChecker.new(user, notify: false).call
    expect(card.reload.revoked_at).to be_present
    expect(card.events.where(kind: 'revoked').count).to eq(1)
  end
end
