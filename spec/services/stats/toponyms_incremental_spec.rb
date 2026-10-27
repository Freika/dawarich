# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Incremental toponym reconciliation' do
  let(:user) { create(:user, settings: { 'timezone' => 'Etc/UTC', 'min_minutes_spent_in_city' => 0 }) }

  before do
    clear_geocoded_days
    Sidekiq.redis do |redis|
      redis.del(Stats::ToponymsRefresh::CURSOR_KEY, Stats::ToponymsRefresh::DISCOVERY_KEY,
                Stats::ToponymsRefresh::TURN_KEY)
    end
  end

  def sweep
    Sidekiq.redis { |redis| redis.set(Stats::ToponymsRefresh::CURSOR_KEY, 0) }
    statements = []
    ActiveSupport::Notifications.subscribed(->(*args) { statements << args.last[:sql] }, 'sql.active_record') do
      Stats::ToponymsRefreshJob.perform_now
    end
    statements.grep(/DECLARE stats_toponyms_/)
  end

  it 'recovers country-only months without pending geocoding work' do
    create(:point, user: user, timestamp: Time.utc(2014, 6, 15).to_i,
                   country_name: 'Germany', city: nil, reverse_geocoded_at: Time.current)
    stat = create(:stat, user: user, year: 2014, month: 6, toponyms: [])
    clear_geocoded_days

    expect(sweep.size).to eq(1)
    expect(stat.reload.toponyms).to eq([{ 'country' => 'Germany', 'cities' => [] }])
    expect(sweep).to be_empty
  end

  it 'rescans stale toponyms with a matching legacy checkpoint' do
    create(:point, user: user, timestamp: Time.utc(2014, 6, 15).to_i,
                   country_name: 'Germany', city: nil, reverse_geocoded_at: Time.current)
    stat = create(:stat, user: user, year: 2014, month: 6, toponyms: [])
    refresh = Stats::RefreshToponyms.new(user, 2014, 6, only_if_changed: true)
    source = refresh.send(:source_signature)
    Rails.cache.write("stats/toponyms_source/v1/#{user.id}/2014/6", refresh.send(:signature, source, stat.toponyms))
    clear_geocoded_days

    expect(sweep.size).to eq(1)
    expect(stat.reload.toponyms).to eq([{ 'country' => 'Germany', 'cities' => [] }])
    expect(sweep).to be_empty
  end

  it 'does not stream unchanged months again and only rescans a month with changed points' do
    stats = [6, 8].map do |month|
      create(:point, user: user, timestamp: Time.utc(2014, month, 15).to_i, city: 'Berlin', country: 'Germany')
      create(:stat, user: user, year: 2014, month: month, toponyms: [])
    end
    expect(sweep.size).to eq(2)
    expect(stats.map { |stat| stat.reload.toponyms.first['country'] }).to eq(%w[Germany Germany])
    expect(sweep).to be_empty
    user.points.where(timestamp: Time.utc(2014, 6, 15).to_i).update_all(city: 'Munich')
    expect(sweep.size).to eq(1)
    expect(stats.first.reload.toponyms.first['cities'].first['city']).to eq('Munich')
    user.points.where(timestamp: Time.utc(2014, 6, 15).to_i).delete_all
    expect(sweep.size).to eq(1)
    expect(stats.first.reload.toponyms).to be_empty
  end

  it 'rebuilds when city-duration settings or an existing result change' do
    create(:point, user: user, timestamp: Time.utc(2014, 6, 15).to_i, city: 'Berlin', country: 'Germany')
    stat = create(:stat, user: user, year: 2014, month: 6, toponyms: [])
    expect(sweep.size).to eq(1)
    expect(sweep).to be_empty
    user.update!(settings: user.settings.merge('min_minutes_spent_in_city' => 60))
    expect(sweep.size).to eq(1)
    expect(stat.reload.toponyms.first['cities']).to be_empty
    stat.update_columns(toponyms: [{ country: 'France', cities: [] }])
    expect(sweep.size).to eq(1)
    expect(stat.reload.toponyms.first['country']).to eq('Germany')
  end
end
