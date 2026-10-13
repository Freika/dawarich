# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Historical achievement visit dates' do
  let(:user) { create(:user) }
  let(:first_at) { Time.utc(2026, 1, 1).to_i }
  let(:wide_geometry) { 'MULTIPOLYGON (((11 48, 11 49, 12 49, 12 48, 11 48)))' }

  def seed_history(region_geometry: wide_geometry, longitude: 11.5, country_geometry: wide_geometry)
    create(:region, code: 'DE-BY', geom: region_geometry)
    country = create(:country, name: 'Germany', iso_a2: 'DE', iso_a3: 'DEU', geom: country_geometry)
    8.times do |index|
      create(:point, user: user, longitude: longitude, latitude: 48.5,
                     timestamp: first_at + (index * 600), country_id: country.id)
    end
    user.points.update_all(country_id: country.id)
  end

  def progress
    Achievements::Progress.find_by!(user: user, achievement_key: 'exploration')
  end

  it 'repairs a persisted check-time date when explicitly recomputing old history' do
    seed_history
    Achievements::RegionSetChecker.new(user, notify: false).call
    progress.update!(state: progress.state.merge('earned' => { 'DE-BY' => Time.current.utc.iso8601,
                                                              'DE' => Time.current.utc.iso8601 }))

    Achievements::RegionSetChecker.new(user, notify: false, oldest_timestamp: first_at - 1).call

    expect(Time.iso8601(progress.state.fetch('earned').fetch('DE-BY')).to_i).to eq(first_at)
  end

  it 'uses the historical date for a region credited by a boundary grid cell' do
    seed_history(region_geometry: 'MULTIPOLYGON (((11.504 48, 11.504 49, 12 49, 12 48, 11.504 48)))',
                 longitude: 11.501)

    Achievements::RegionSetChecker.new(user, notify: false).call

    expect(progress.state.fetch('dwell').fetch('DE-BY')).to eq(4200)
    expect(Time.iso8601(progress.state.fetch('earned').fetch('DE-BY')).to_i).to eq(first_at)
  end

  it 'uses the historical date for a country credited through country_id' do
    seed_history(country_geometry: 'MULTIPOLYGON (((10 48, 10 49, 11 49, 11 48, 10 48)))')

    Achievements::RegionSetChecker.new(user, notify: false).call

    expect(progress.state.fetch('dwell').fetch('DE')).to eq(4200)
    expect(Time.iso8601(progress.state.fetch('earned').fetch('DE')).to_i).to eq(first_at)
  end

  it 'repairs legacy progress through a silent stale-only backfill exactly once' do
    seed_history
    Achievements::RegionSetChecker.new(user, notify: false).call
    progress.update!(state: progress.state.merge('calculation_version' => 3,
                                                 'earned' => { 'DE-BY' => Time.current.utc.iso8601,
                                                               'DE' => Time.current.utc.iso8601 }))
    award = create(:user_achievement, user: user, achievement_key: 'country_de', earned_at: Time.at(first_at).utc)

    expect do
      perform_enqueued_jobs(only: Achievements::CheckJob) do
        Achievements::BulkCheckJob.perform_now(notify: false, force: true, stale_only: true)
      end
    end.not_to(change { [user.notifications.count, user.achievement_unlock_events.count] })

    expect(Time.iso8601(progress.state.fetch('earned').fetch('DE-BY')).to_i).to eq(first_at)
    expect(Time.iso8601(progress.state.fetch('earned').fetch('DE')).to_i).to eq(first_at)
    expect(progress.state.fetch('calculation_version')).to eq(Achievements::RegionSetChecker::CALCULATION_VERSION)
    expect(award.reload.earned_at.to_i).to eq(first_at)

    clear_enqueued_jobs
    Achievements::BulkCheckJob.perform_now(notify: false, force: true, stale_only: true)
    expect(enqueued_jobs.select { |job| job[:job] == Achievements::CheckJob }).to be_empty
  end

  it 'preserves known earlier visit dates when their points have been removed' do
    seed_history
    Achievements::RegionSetChecker.new(user, notify: false).call
    known_at = Time.at(first_at - 30.days).utc.iso8601
    earned = { 'DE-BY' => known_at, 'DE' => known_at }
    progress.update!(state: progress.state.merge('calculation_version' => 3, 'earned' => earned))

    Achievements::RegionSetChecker.new(user, notify: false).call

    expect(progress.state.fetch('earned')).to eq(earned)
  end

  it 'retains existing awards when no historical points remain' do
    seed_history
    Achievements::RegionSetChecker.new(user, notify: false).call
    earned = progress.state.fetch('earned')
    progress.update!(state: progress.state.merge('calculation_version' => 3))
    user.points.delete_all

    Achievements::RegionSetChecker.new(user, notify: false).call

    expect(progress.state.fetch('earned')).to eq(earned)
    expect(progress.state.fetch('dwell')).to be_empty
  end

  it 'uses the spatial country fallback when country IDs are unavailable' do
    seed_history
    user.points.update_all(country_id: nil)

    Achievements::RegionSetChecker.new(user, notify: false).call

    expect(Time.iso8601(progress.state.fetch('earned').fetch('DE')).to_i).to eq(first_at)
  end

  it 'dates an incremental spatial country award when older history has populated IDs' do
    seed_history
    germany = Country.find_by!(iso_a2: 'DE')
    92.times do |index|
      create(:point, user: user, longitude: 11.5, latitude: 48.5,
                     timestamp: first_at + 5000 + index * 10)
    end
    user.points.update_all(country_id: germany.id)
    Achievements::RegionSetChecker.new(user, notify: false).call
    create(:country, name: 'France', iso_a2: 'FR', iso_a3: 'FRA',
                     geom: 'MULTIPOLYGON (((2 48, 2 49, 3 49, 3 48, 2 48)))')
    france_at = first_at + 2.days.to_i
    8.times do |index|
      create(:point, user: user, longitude: 2.5, latitude: 48.5, timestamp: france_at + index * 600)
    end
    user.points.where('timestamp >= ?', france_at).update_all(country_id: nil)

    Achievements::RegionSetChecker.new(user, notify: false).call

    expect(progress.state.fetch('dwell').fetch('FR')).to eq(4200)
    expect(Time.iso8601(progress.state.fetch('earned').fetch('FR')).to_i).to eq(france_at)
  end

  it 'dates an incremental country ID award when older history lacks IDs' do
    seed_history
    user.points.update_all(country_id: nil)
    Achievements::RegionSetChecker.new(user, notify: false).call
    france = create(:country, name: 'France', iso_a2: 'FR', iso_a3: 'FRA',
                              geom: 'MULTIPOLYGON (((2 48, 2 49, 3 49, 3 48, 2 48)))')
    france_at = first_at + 2.days.to_i
    9.times do |index|
      create(:point, user: user, longitude: 5.5, latitude: 48.5, timestamp: france_at + index * 600)
    end
    user.points.where('timestamp >= ?', france_at).update_all(country_id: france.id)

    Achievements::RegionSetChecker.new(user, notify: false).call

    expect(progress.state.fetch('dwell').fetch('FR')).to eq(4800)
    expect(Time.iso8601(progress.state.fetch('earned').fetch('FR')).to_i).to eq(france_at)
  end

  it 'preserves an earlier ungeocoded visit when a later ID-tagged visit earns the country' do
    france = create(:country, name: 'France', iso_a2: 'FR', iso_a3: 'FRA', geom: wide_geometry)
    3.times do |index|
      create(:point, user: user, longitude: 11.5, latitude: 48.5, timestamp: first_at + index * 600)
    end
    user.points.update_all(country_id: nil)
    Achievements::RegionSetChecker.new(user, notify: false).call
    expect(progress.state.fetch('earned')).not_to have_key('FR')
    later_at = first_at + 2.days.to_i
    9.times do |index|
      create(:point, user: user, longitude: 11.5, latitude: 48.5, timestamp: later_at + index * 600)
    end
    user.points.where('timestamp >= ?', later_at).update_all(country_id: france.id)

    Achievements::RegionSetChecker.new(user, notify: false).call

    expect(Time.iso8601(progress.state.fetch('earned').fetch('FR')).to_i).to eq(first_at)
  end

  it 'trusts populated country IDs when earlier points intersect another country' do
    seed_history(country_geometry: 'MULTIPOLYGON (((10 48, 10 49, 11 49, 11 48, 10 48)))')
    france = create(:country, name: 'France', iso_a2: 'FR', iso_a3: 'FRA', geom: wide_geometry)
    Achievements::RegionSetChecker.new(user, notify: false).call
    later_at = first_at + 2.days.to_i
    9.times do |index|
      create(:point, user: user, longitude: 11.5, latitude: 48.5, timestamp: later_at + index * 600)
    end
    user.points.where('timestamp >= ?', later_at).update_all(country_id: france.id)

    Achievements::RegionSetChecker.new(user, notify: false).call

    expect(Time.iso8601(progress.state.fetch('earned').fetch('FR')).to_i).to eq(later_at)
  end

  it 'ignores older anomalous points when dating first visits' do
    seed_history
    create(:point, user: user, longitude: 11.5, latitude: 48.5, timestamp: first_at - 10_000, anomaly: true)

    Achievements::RegionSetChecker.new(user, notify: false).call

    expect(Time.iso8601(progress.state.fetch('earned').fetch('DE-BY')).to_i).to eq(first_at)
    expect(Time.iso8601(progress.state.fetch('earned').fetch('DE')).to_i).to eq(first_at)
  end
end
