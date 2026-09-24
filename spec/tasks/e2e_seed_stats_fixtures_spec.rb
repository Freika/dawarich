# frozen_string_literal: true

require 'rails_helper'

describe 'e2e:seed_stats_fixtures' do
  let(:reader) { User.find_by!(email: 'e2e-stats@dawarich.test') }
  let(:actor) { User.find_by!(email: 'e2e-stats-actions@dawarich.test') }
  let(:empty) { User.find_by!(email: 'e2e-stats-empty@dawarich.test') }

  before { Rake::Task['e2e:seed_stats_fixtures'].execute }

  it 'creates active users with the pinned password, timezone and distance unit' do
    [reader, actor, empty].each do |user|
      expect(user.valid_password?('safepassword12')).to be(true)
      expect(user).to be_active
      expect(user.safe_settings.timezone).to eq('Europe/Berlin')
      expect(user.safe_settings.distance_unit).to eq('km')
    end
  end

  it 'derives the pinned monthly and daily distances from the walks' do
    expect(reader.stats.order(:year, :month).pluck(:year, :month, :distance))
      .to eq([[2023, 7, 20_030], [2024, 3, 38_054], [2024, 4, 12_018]])

    march = reader.stats.find_by!(year: 2024, month: 3)
    expect(march.daily_distance.select { |_day, meters| meters.positive? })
      .to eq([[5, 10_015], [6, 6_009], [7, 14_021], [20, 8_009]])
  end

  it 'keeps the cities that pass the one-hour threshold' do
    march = reader.stats.find_by!(year: 2024, month: 3)
    places = march.toponyms.map { |t| [t['country'], t['cities'].map { |c| [c['city'], c['stayed_for']] }] }

    expect(places).to eq([['Germany', [['Berlin', 3020]]], ['Czechia', [['Prague', 80]]]])
  end

  it 'marks every point geocoded, leaves one without place data and counts them' do
    expect(reader.points_count).to eq(77)
    expect(reader.points.where(reverse_geocoded_at: nil).count).to eq(0)
    expect(reader.points.where(city: nil).count).to eq(1)
    expect(reader.visits.confirmed.group(:name).count).to eq('Office' => 2, 'Home' => 1)
  end

  it 'precomputes digests for the read-only user only' do
    expect(reader.digests.order(:period_type, :year, :month).pluck(:period_type, :year, :month)).to eq(
      [['monthly', 2023, 7], ['monthly', 2024, 3], ['monthly', 2024, 4], ['yearly', 2023, nil], ['yearly', 2024, nil]]
    )

    yearly = reader.digests.yearly.find_by!(year: 2024)
    expect(yearly.first_time_countries).to eq(['Czechia'])
    expect(yearly.yoy_distance_change).to eq(150)
    expect(reader.digests.monthly.find_by!(year: 2024, month: 4).mom_distance_change).to eq(-68)

    expect(actor.stats.count).to eq(3)
    expect(actor.digests.count).to eq(0)
    expect(empty.points.count).to eq(0)
    expect(empty.stats.count).to eq(0)
  end

  it 'replaces rather than duplicates the fixture on a second run' do
    Rake::Task['e2e:seed_stats_fixtures'].execute

    expect(reader.points.count).to eq(77)
    expect(reader.reload.points_count).to eq(77)
    expect(reader.stats.count).to eq(3)
    expect(reader.digests.count).to eq(5)
    expect(reader.visits.count).to eq(3)
  end
end
