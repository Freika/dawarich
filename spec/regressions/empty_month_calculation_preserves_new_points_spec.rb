# frozen_string_literal: true

require 'rails_helper'

# Deliberately avoids :non_transactional, whose shared helper truncates tables.
# This standalone group cleans only the user/rows it creates.
RSpec.describe 'Empty monthly calculation after historical points arrive', type: :request do
  before(:context) { self.class.use_transactional_tests = false }
  after(:context) { self.class.use_transactional_tests = true }

  it 'does not let an older empty calculation erase completed historical recovery' do
    owner = create(:user, stats_swept_at: Time.current,
                          settings: { 'timezone' => 'Asia/Tokyo', 'min_minutes_spent_in_city' => 10 })
    existing_country = Country.find_by(iso_a2: 'DE')
    country = existing_country || create(:country, name: 'Germany', iso_a2: 'DE', iso_a3: 'DEU')
    stat = create(:stat, user: owner, year: 2015, month: 1, toponyms: [], calculation_version: 0)
    allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true)
    allow(Geocoder).to receive(:search).and_return([double(city: 'Berlin', country: country.name, country_code: 'DE',
                                                           data: {})])
    empty_read = Concurrent::CountDownLatch.new(1)
    release_old = Concurrent::CountDownLatch.new(1)
    calculator = Stats::CalculateMonth.new(owner.id, 2015, 1)
    allow(calculator).to receive(:reset_month_stats).and_wrap_original do |original, *args|
      empty_read.count_down
      raise 'Timed out releasing old calculation' unless release_old.wait(15)

      original.call(*args)
    end
    old_pid = nil
    old = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        old_pid = connection.select_value('SELECT pg_backend_pid()')
        calculator.call
      end
    end
    expect(empty_read.wait(10)).to be(true)
    new_pid = ActiveRecord::Base.connection.select_value('SELECT pg_backend_pid()')
    expect(old_pid).not_to eq(new_pid)
    points = 3.times.map do |i|
      create(:point, user: owner, timestamp: Time.utc(2014, 12, 31, 23, i * 10).to_i,
                     latitude: 52.52, longitude: 13.405)
    end
    points.each { |point| ReverseGeocoding::Points::FetchData.new(point.id).call }
    expect(stat.reload.calculation_version).to eq(0)
    Stats::CalculatingJob.perform_now(owner.id, 2015, 1)
    expect(stat.reload.toponyms).not_to be_empty
    expect(stat.calculation_version).to eq(Stats::CalculateMonth::CALCULATION_VERSION)
    release_old.count_down
    expect(old.join(10)).not_to be_nil
    old.value
    clear_enqueued_jobs
    Stats::BulkCalculator.new(owner.id).call
    repairs = enqueued_jobs.count { |job| job[:job] == Stats::CalculatingJob }
    expect(stat.toponyms.present? || repairs.positive?).to be(true),
                                                           'Previously recovered historical country/city data was erased and no repair remains eligible'
  ensure
    release_old&.count_down
    old&.join(20)
    if owner
      Cache::InvalidateUserCaches.new(owner.id).call
      Point.where(user_id: owner.id).delete_all
      Stat.where(user_id: owner.id).delete_all
      owner.destroy!
    end
    country&.destroy! if defined?(existing_country) && existing_country.nil?
  end
end
