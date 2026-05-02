# frozen_string_literal: true

require 'rails_helper'

# Regression for https://github.com/Freika/dawarich/issues/2581
RSpec.describe 'Countries-visited consistency between insights and statistics',
               type: :helper do
  helper StatsHelper

  let(:user) { create(:user) }

  let!(:stat) do
    create(
      :stat,
      user: user, year: 2026, month: 4,
      toponyms: [
        # Real visit: country with at least one city
        { 'country' => 'Germany', 'cities' => [{ 'city' => 'Berlin' }] },
        # Border-crossing artifact: country with no city resolved
        { 'country' => 'France', 'cities' => [] }
      ]
    )
  end

  it 'agrees on the number of countries visited in the month' do
    insights_countries = Users::Digests::MonthlyFirstTimeVisitsCalculator
                         .new(user, 2026, 4).call['countries']
    stats_country_count = helper.countries_visited(stat)

    expect(insights_countries.size).to eq(stats_country_count),
                                       'Insights and statistics views report a different number of countries ' \
                                       "for the same Stat. Insights: #{insights_countries.inspect}, " \
                                       "Statistics count: #{stats_country_count}. " \
                                       'See https://github.com/Freika/dawarich/issues/2581'
  end
end
