# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Visited island country achievements' do
  let(:user) { create(:user, settings: { 'min_minutes_spent_in_city' => 60 }) }
  # Reuse a flat achievement's code, but invent its name and its entire geometry
  # in open ocean. These coordinates do not represent New Caledonia or a real visit.
  let!(:island) do
    create(:country, name: 'Synthetic Island', iso_a2: 'NC', iso_a3: 'NCL',
                     geom: 'MULTIPOLYGON (((-140.0098 -40.0098, -140.0072 -40.0098, ' \
                           '-140.0072 -40.0072, -140.0098 -40.0072, -140.0098 -40.0098)))')
  end
  let(:base_ts) { Time.utc(2026, 1, 1).to_i }

  # Imported points may not have country_id yet. Keep them untagged so that
  # achievements locate them spatially, without running geocoding jobs.
  def insert_untagged_island_hour
    Point.insert_all!(7.times.map do |index|
      { user_id: user.id, country_id: nil, lonlat: 'POINT(-140.009 -40.009)',
        timestamp: base_ts + index * 600, created_at: Time.current, updated_at: Time.current }
    end)
  end

  def expect_island_earned
    Achievements::RegionSetChecker.new(user, notify: false).call

    progress = Achievements::Progress.find_by!(user: user, achievement_key: 'exploration')
    expect(progress.state.fetch('earned')).to have_key('NC')
    expect(user.user_achievements.pluck(:achievement_key)).to include('country_nc')
  end

  it 'earns a country after an hour inside its border even when the grid centre is offshore' do
    insert_untagged_island_hour

    expect(Country.containing_point(-140.009, -40.009)&.id).to eq(island.id)
    expect(Country.containing_point(-140.005, -40.005)).to be_nil
    expect(user.points.where(country_id: nil).count).to eq(7)

    expect_island_earned
  end

  it 'earns it on the country_id path too, when most other points are already tagged' do
    mainland = create(:country, name: 'Synthetic Mainland', iso_a2: 'TO', iso_a3: 'TON',
                                geom: 'MULTIPOLYGON (((-150.5 -45.5, -149.5 -45.5, -149.5 -44.5, ' \
                                      '-150.5 -44.5, -150.5 -45.5)))')
    Point.insert_all!(70.times.map do |index|
      { user_id: user.id, country_id: mainland.id, lonlat: 'POINT(-150 -45)',
        timestamp: base_ts - 1.day.to_i + index * 60, created_at: Time.current, updated_at: Time.current }
    end)
    insert_untagged_island_hour

    expect(user.points.where.not(country_id: nil).count.to_f / user.points.count)
      .to be >= Achievements::CountryDwellCalculator::COVERAGE_THRESHOLD

    expect_island_earned
  end
end
