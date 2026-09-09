# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Geocoded statistics commit recovery', :non_transactional, threads: 3 do
  include ActiveSupport::Testing::TimeHelpers

  around do |example|
    country_ids = Country.pluck(:id)
    stat_ids = Stat.pluck(:id)
    example.run
  ensure
    Stat.where.not(id: stat_ids).delete_all
    Country.where.not(id: country_ids).delete_all
  end

  let(:user) { create(:user, settings: { 'timezone' => 'Etc/UTC', 'min_minutes_spent_in_city' => 0 }) }
  let(:point) { create(:point, user: user, timestamp: Time.utc(2014, 6, 15).to_i) }
  let(:stat) { create(:stat, user: user, year: 2014, month: 6, toponyms: []) }

  before do
    clear_geocoded_days
    Sidekiq.redis do |r|
      r.del(
        Stats::ToponymsRefresh::TURN_KEY, Stats::ToponymsRefresh::CURSOR_KEY
      )
    end
    allow(Geocoding::Search).to receive(:call).and_return([
                                                            double(city: 'Berlin', country: 'Germany',
                                                                   country_code: 'DE', data: {})
                                                          ])
  end

  after do
    clear_geocoded_days
    Stat.where(user_id: user.id).delete_all
  end

  it 'does not publish changes rolled back by an enclosing transaction' do
    point.id
    Point.transaction do
      ReverseGeocoding::Points::FetchData.new(point.id).call
      raise ActiveRecord::Rollback
    end
    expect(point.reload.city).to be_nil
    travel 61.minutes do
      expect(Stats::GeocodedDays.due(limit: 10)).to be_empty
    end
  end

  it 'uses a successful normal calculation to consume the pending update' do
    stat.id
    ReverseGeocoding::Points::FetchData.new(point.id).call
    Stats::CalculateMonth.new(user.id, 2014, 6).call
    expect(stat.reload.toponyms.first['country']).to eq('Germany')
    travel 61.minutes do
      expect(Stats::GeocodedDays.due(limit: 10)).to be_empty
    end
  end

  it 'does not acknowledge a full calculation rolled back by its caller' do
    stat.id
    ReverseGeocoding::Points::FetchData.new(point.id).call
    Stat.transaction do
      Stats::CalculateMonth.new(user.id, 2014, 6).call
      raise ActiveRecord::Rollback
    end
    expect(stat.reload.toponyms).to be_empty
    travel 61.minutes do
      expect(Stats::GeocodedDays.due(limit: 10)).not_to be_empty
    end
  end

  it 'does not create an empty neighbouring month for a timezone boundary notification' do
    user.update!(settings: { 'timezone' => 'Asia/Tokyo', 'min_minutes_spent_in_city' => 0 })
    point.update!(timestamp: Time.utc(2014, 12, 31, 23, 30).to_i)
    january = create(:stat, user: user, year: 2015, month: 1, toponyms: [])
    ReverseGeocoding::Points::FetchData.new(point.id).call
    travel 61.minutes do
      Stats::ToponymsRefreshJob.perform_now
      expect(Stats::GeocodedDays.due(limit: 10)).to be_empty
    end
    expect(user.stats.pluck(:year, :month)).to eq([[2015, 1]])
    expect(january.reload.toponyms.first['country']).to eq('Germany')
  end

  it 'retries cache invalidation after the result has already committed' do
    stat.id
    ReverseGeocoding::Points::FetchData.new(point.id).call
    allow(Rails.cache).to receive(:delete).and_raise(IOError, 'cache unavailable')
    expect { Stats::RefreshToponyms.new(user, 2014, 6, invalidate_cache: true).call }.to raise_error(IOError)
    expect(stat.reload.toponyms.first['country']).to eq('Germany')
    allow(Rails.cache).to receive(:delete).and_call_original
    travel 61.minutes do
      Stats::ToponymsRefreshJob.perform_now
      expect(Stats::GeocodedDays.due(limit: 10)).to be_empty
    end
    expect(Rails.cache).to have_received(:delete).with("dawarich/user_#{user.id}_countries_visited").twice
  end

  it 'excludes a second worker while another connection holds the global refresh lock' do
    stat.id
    ReverseGeocoding::Points::FetchData.new(point.id).call
    lock = Stats::ToponymsRefresh::LOCK_ID
    connection = ActiveRecord::Base.connection
    connection.execute("SELECT pg_advisory_lock(#{lock})")
    travel 61.minutes do
      other = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection { Stats::ToponymsRefreshJob.perform_now }
      end
      expect(other.join(5)).not_to be_nil
      other.value
      expect(stat.reload.toponyms).to be_empty
      expect(Stats::GeocodedDays.due(limit: 10)).not_to be_empty
    end
  ensure
    connection&.execute("SELECT pg_advisory_unlock(#{lock})")
  end
end
