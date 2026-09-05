# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Geocoding during monthly calculation', :non_transactional, threads: 3 do
  include ActiveSupport::Testing::TimeHelpers

  around do |example|
    country_ids = Country.pluck(:id)
    stat_ids = Stat.pluck(:id)
    example.run
  ensure
    Stat.where.not(id: stat_ids).delete_all
    Country.where.not(id: country_ids).delete_all
  end

  before { Sidekiq.redis { |r| r.del(Stats::GeocodedDays::PENDING_KEY, Stats::GeocodedDays::VERSIONS_KEY) } }
  after { Sidekiq.redis { |r| r.del(Stats::GeocodedDays::PENDING_KEY, Stats::GeocodedDays::VERSIONS_KEY) } }

  it 'does not block geocoding or lose changes committed after the monthly snapshot' do
    user = create(:user, settings: { 'timezone' => 'Etc/UTC', 'min_minutes_spent_in_city' => 0 })
    point = create(:point, user: user, timestamp: Time.utc(2014, 6, 15, 12).to_i)
    stat = create(:stat, user: user, year: 2014, month: 6, toponyms: [], calculation_version: 0)
    allow(Geocoding::Search).to receive(:call).and_return([
                                                            double(city: 'Berlin', country: 'Germany',
                                                                   country_code: 'DE', data: {})
                                                          ])
    read_points = Concurrent::CountDownLatch.new(1)
    release_calculation = Concurrent::CountDownLatch.new(1)
    observer = lambda do |*args|
      sql = args.last[:sql]
      unless Thread.current[:pause_stats_read] && sql.include?('FROM "points"') &&
             sql.include?('EXTRACT(year FROM (to_timestamp(timestamp)')
        next
      end

      Thread.current[:pause_stats_read] = false
      read_points.count_down
      raise 'calculation release timed out' unless release_calculation.wait(10)
    end
    ActiveSupport::Notifications.subscribed(observer, 'sql.active_record') do
      calculation = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          Thread.current[:pause_stats_read] = true
          Stats::CalculateMonth.new(user.id, 2014, 6).call
        end
      end
      expect(read_points.wait(10)).to be(true)
      geocoding = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ReverseGeocoding::Points::FetchData.new(point.id).call
        end
      end
      expect(geocoding.join(5)).not_to be_nil
      geocoding.value
      release_calculation.count_down
      expect(calculation.join(10)).not_to be_nil
      calculation.value
    ensure
      release_calculation.count_down
      [calculation, geocoding].compact.each { |thread| thread.join(10) }
    end
    expect(point.reload.city).to eq('Berlin')
    expect(stat.reload.toponyms).to be_empty
    travel 61.minutes do
      expect(Stats::GeocodedDays.due(limit: 10)).not_to be_empty
      Stats::ToponymsRefreshJob.perform_now
    end
    expect(stat.reload.toponyms.first['country']).to eq('Germany')
  ensure
    Stat.where(user_id: user&.id).delete_all
  end
end
