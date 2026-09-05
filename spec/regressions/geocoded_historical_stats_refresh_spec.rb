# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Geocoded historical statistics', :non_transactional do
  include ActiveSupport::Testing::TimeHelpers

  around do |example|
    country_ids = Country.pluck(:id)
    stat_ids = Stat.pluck(:id)
    example.run
  ensure
    Stat.where.not(id: stat_ids).delete_all
    Country.where.not(id: country_ids).delete_all
  end
  before do
    Sidekiq.redis { |r| r.del(Stats::GeocodedDays::PENDING_KEY, Stats::GeocodedDays::VERSIONS_KEY) }
  end

  after do
    Sidekiq.redis { |r| r.del(Stats::GeocodedDays::PENDING_KEY, Stats::GeocodedDays::VERSIONS_KEY) }
  end

  it 'refreshes a historical month after geocoding without per-point statistics SQL' do
    user = create(:user, stats_swept_at: Time.current,
                         settings: { 'timezone' => 'Etc/UTC', 'min_minutes_spent_in_city' => 0 })
    point = create(:point, user: user, timestamp: Time.utc(2014, 6, 15, 12).to_i)
    stat = create(:stat, user: user, year: 2014, month: 6, toponyms: [], distance: 123,
                         calculation_version: Stats::CalculateMonth::CALCULATION_VERSION)
    country = create(:country, name: 'Germany', iso_a2: 'DE', iso_a3: 'DEU')
    allow(Geocoding::Search).to receive(:call).and_return([
                                                            double(city: 'Berlin', country: country.name,
                                                                   country_code: 'DE', data: {})
                                                          ])
    queries = []
    ActiveSupport::Notifications.subscribed(->(*args) { queries << args.last[:sql] }, 'sql.active_record') do
      ReverseGeocoding::Points::FetchData.new(point.id).call
    end
    expect(point.reload.city).to eq('Berlin')
    expect(queries.grep(/\b(?:stats|users)\b/)).to be_empty
    expect(stat.reload.toponyms).to be_empty
    travel 61.minutes do
      Stats::ToponymsRefreshJob.perform_now
    end
    expect(stat.reload.toponyms.first['country']).to eq('Germany')
    expect(stat.distance).to eq(123)
  end

  it 'recovers a committed point whose Redis notification was lost' do
    user = create(:user, settings: { 'timezone' => 'Etc/UTC', 'min_minutes_spent_in_city' => 0 })
    create(:point, user: user, timestamp: Time.utc(2014, 6, 15, 12).to_i,
                   city: 'Berlin', country: 'Germany', reverse_geocoded_at: Time.current, velocity: 0)
    stat = create(:stat, user: user, year: 2014, month: 6, toponyms: [])
    Sidekiq.redis { |r| r.set(Stats::ToponymsRefreshJob::CURSOR_KEY, stat.id - 1) }
    Stats::ToponymsRefreshJob.perform_now
    expect(stat.reload.toponyms.first['country']).to eq('Germany')
  end
end
