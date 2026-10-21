# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Yearly Insights includes countries visited for less than an hour' do
  let(:user) { create(:user, settings: { 'min_minutes_spent_in_city' => 60 }) }
  let(:start_timestamp) { Time.utc(2026, 4, 15, 12).to_i }

  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)

    [
      ['Liechtenstein', 'Synthetic Transit Town', [0, 10, 20]],
      ['Germany', 'Synthetic Stay Town', [30, 60, 90, 100]]
    ].each do |country, city, minutes|
      minutes.each do |minute|
        # Made-up ocean coordinates; country labels represent pre-geocoded data.
        create(:point, user: user, country_name: country, city: city, velocity: 0,
                       timestamp: start_timestamp + minute * 60,
                       lonlat: "POINT(#{-140 + minute * 0.00001} -50)",
                       reverse_geocoded_at: Time.current)
      end
    end

    Stats::CalculateMonth.new(user.id, 2026, 4).call
  end

  it 'counts the country retained in monthly toponyms even when no city meets the stay threshold' do
    stat = user.stats.find_by!(year: 2026, month: 4)
    expect(user.points.where(country_name: 'Liechtenstein').count).to eq(3)
    expect(user.points.not_reverse_geocoded).to be_empty
    expect(stat.toponyms).to include('country' => 'Liechtenstein', 'cities' => [])

    totals = Insights::YearTotalsCalculator.new(user.stats.where(year: 2026), distance_unit: 'km').call

    aggregate_failures 'yearly country totals' do
      expect(totals.countries_count).to eq(2)
      expect(totals.countries_list).to contain_exactly('Germany', 'Liechtenstein')
      expect(totals.cities_count).to eq(1)
    end
  end
end
