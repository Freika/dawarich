# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Insights and statistics report the same countries visited' do
  let(:user) { create(:user) }

  let!(:stat) do
    create(:stat, user: user, year: 2026, month: 4, distance: 100, toponyms: [
             { 'country' => 'Germany', 'cities' => [{ 'city' => 'Berlin', 'stayed_for' => 480 }] },
             { 'country' => 'France', 'cities' => [] },
             { 'country' => 'Austria' }
           ])
  end

  def insights_countries
    Insights::YearTotalsCalculator.new(user.stats.where(year: 2026), distance_unit: 'km').call.countries_list
  end

  def statistics_countries
    user.countries_visited_uncached
  end

  it 'excludes countries without qualifying cities from the insights count' do
    expect(insights_countries).to eq(['Germany'])
  end

  it 'agrees with statistics on the set of countries visited' do
    expect(insights_countries).to eq(statistics_countries)
  end
end
