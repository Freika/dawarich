# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Flown-over countries are excluded from travel summaries' do
  let(:user) { create(:user, settings: { 'min_minutes_spent_in_city' => 60 }) }
  let(:started_at) { Time.utc(2025, 4, 15, 8) }

  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)

    [
      ['Portugal', 'Synthetic Departure', 0, [0, 15, 30, 45, 60, 75]],
      ['Germany', 'Synthetic Flyover', 250, [90, 100]],
      ['Japan', 'Synthetic Arrival', 0, [120, 135, 150, 165, 180, 195]]
    ].each do |country, city, velocity, minutes|
      minutes.each do |minute|
        # Made-up ocean coordinates with synthetic, pre-geocoded country labels.
        # Velocity is stored in m/s: 250 m/s is 900 km/h.
        create(:point, user: user, country_name: country, city: city, velocity: velocity,
                       timestamp: (started_at + minute.minutes).to_i,
                       lonlat: "POINT(#{-140 + minute * 0.00001} -50)",
                       reverse_geocoded_at: Time.current)
      end
    end

    Stats::CalculateMonth.new(user.id, 2025, 4).call
  end

  it 'already excludes the flyover from monthly statistics' do
    countries = user.stats.find_by!(year: 2025, month: 4).toponyms.map { |entry| entry['country'] }

    expect(countries).to contain_exactly('Portugal', 'Japan')
  end

  it 'excludes the flyover when recalculating trip countries' do
    trip = create(:trip, user: user, started_at: started_at, ended_at: started_at + 4.hours,
                         skip_calculation_enqueue: true)

    trip.calculate_countries
    trip.save!

    expect(trip.reload.visited_countries).to contain_exactly('Portugal', 'Japan')
  end

  it 'excludes the flyover from yearly digest time spent by country' do
    digest = Users::Digests::CalculateYear.new(user.id, 2025).call

    aggregate_failures do
      expect(digest.countries_count).to eq(2)
      expect(digest.first_time_countries).to contain_exactly('Portugal', 'Japan')
      expect(digest.top_countries_by_time.map { |country| country['name'] })
        .to contain_exactly('Portugal', 'Japan')
    end
  end

  it 'excludes the flyover from monthly digest time spent by country' do
    digest = Users::Digests::CalculateMonth.new(user.id, 2025, 4).call

    expect(digest.top_countries_by_time.map { |country| country['name'] })
      .to contain_exactly('Portugal', 'Japan')
  end

  it 'excludes the flyover from Days per Country' do
    residency = Residency::DayCounter.new(user, 2025).call

    expect(residency[:countries].map { |country| country[:country_name] })
      .to contain_exactly('Portugal', 'Japan')
  end
end
