# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Continent counts countries with explored regions' do
  let(:user) { create(:user) }
  let(:base_ts) { Time.utc(2026, 1, 1).to_i }

  # Deliberately fictional boundaries in the South Pacific, far from any home.
  let(:canada_geometry) { 'MULTIPOLYGON (((-140 -50, -140 -49, -139 -49, -139 -50, -140 -50)))' }
  let(:us_geometry) { 'MULTIPOLYGON (((-130 -50, -130 -49, -129 -49, -129 -50, -130 -50)))' }

  def insert_stay(count:, longitude:, country_id:, start_at:)
    # Bulk imports bypass Point's after_create country assignment.
    rows = count.times.map do |index|
      { user_id: user.id, lonlat: "POINT(#{longitude} -49.505)", country_id:,
        timestamp: start_at + index * 600, created_at: Time.current, updated_at: Time.current }
    end
    Point.insert_all!(rows)
  end

  it 'counts both countries when one has untagged points and overall country_id coverage is 90 percent' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    user.update!(settings: user.settings.merge('min_minutes_spent_in_city' => 60))
    canada = create(:country, name: 'Canada', iso_a2: 'CA', iso_a3: 'CAN', geom: canada_geometry)
    create(:country, name: 'United States of America', iso_a2: 'US', iso_a3: 'USA', geom: us_geometry)
    create(:region, code: 'CA-NU', geom: canada_geometry)
    create(:region, code: 'US-AK', geom: us_geometry)
    insert_stay(count: 72, longitude: -139.505, country_id: canada.id, start_at: base_ts)
    insert_stay(count: 8, longitude: -129.505, country_id: nil, start_at: base_ts + 100_000)

    Achievements::RegionSetChecker.new(user, notify: false).call

    state = Achievements::Progress.exploration_for(user).state
    expect(state.fetch('earned').keys).to include('CA', 'CA-NU', 'US-AK')
    continent = Achievements::SetPresenter.new(
      definition: Achievements::Registry.find('continent_north_america'), state:
    )
    expect(continent.region_cards.select { |card| card[:percent].positive? }.map { |card| card[:code] })
      .to contain_exactly('CA', 'US')
    expect(continent.earned_count).to eq(2)
  end
end
