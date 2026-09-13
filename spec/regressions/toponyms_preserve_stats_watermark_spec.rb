# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Toponym refresh preserves the full statistics watermark' do
  it 'still schedules new point months when the account has not been swept yet' do
    user = create(:user, stats_swept_at: nil, settings: { 'timezone' => 'Etc/UTC' })
    create(:stat, user: user, year: 2014, month: 6, updated_at: 2.days.ago, toponyms: [], calculation_version: 1)
    create(:point, user: user, timestamp: Time.utc(2014, 6, 15).to_i, city: 'Berlin', country: 'Germany')
    recent = 1.day.ago.utc
    create(:point, user: user, timestamp: recent.to_i)
    clear_enqueued_jobs

    Stats::RefreshToponyms.new(user, 2014, 6).call
    Stats::BulkCalculator.new(user.id).call

    expect(Stats::CalculatingJob).to have_been_enqueued.with(user.id, recent.year, recent.month)
  end
  it 'rolls back the preserved watermark together with the narrow update' do
    user = create(:user, stats_swept_at: nil, settings: { 'timezone' => 'Etc/UTC' })
    stat = create(:stat, user: user, year: 2014, month: 6, updated_at: 2.days.ago, toponyms: [])
    create(:point, user: user, timestamp: Time.utc(2014, 6, 15).to_i, city: 'Berlin', country: 'Germany')
    before = stat.updated_at
    Stat.transaction(requires_new: true) do
      Stats::RefreshToponyms.new(user, 2014, 6).call
      expect(user.reload.stats_swept_at).to eq(before)
      raise ActiveRecord::Rollback
    end
    expect(user.reload.stats_swept_at).to be_nil
    expect(stat.reload.toponyms).to be_empty
    expect(stat.updated_at).to eq(before)
  end

  it 'does not replace a newer completed sweep through a stale user instance' do
    user = create(:user, stats_swept_at: nil, settings: { 'timezone' => 'Etc/UTC' })
    create(:stat, user: user, year: 2014, month: 6, updated_at: 2.days.ago, toponyms: [])
    create(:point, user: user, timestamp: Time.utc(2014, 6, 15).to_i, city: 'Berlin', country: 'Germany')
    completed = 1.hour.ago.change(usec: 0)
    User.find(user.id).update_column(:stats_swept_at, completed)
    Stats::RefreshToponyms.new(user, 2014, 6).call
    expect(user.reload.stats_swept_at).to eq(completed)
  end
end

RSpec.describe 'Concurrent initial statistics watermark', :non_transactional, threads: 3 do
  it 'uses the preserved watermark even if the sweep read the user before a narrow refresh' do
    user = create(:user, stats_swept_at: nil, settings: { 'timezone' => 'Etc/UTC' })
    stat = create(:stat, user: user, year: 2014, month: 6, updated_at: 2.days.ago, toponyms: [], calculation_version: 1)
    create(:point, user: user, timestamp: Time.utc(2014, 6, 15).to_i, city: 'Berlin', country_name: 'Germany')
    recent = 1.day.ago.utc
    create(:point, user: user, timestamp: recent.to_i)
    clear_enqueued_jobs
    read_user = Concurrent::CountDownLatch.new(1)
    release_sweep = Concurrent::CountDownLatch.new(1)
    observer = lambda do |*args|
      next unless Thread.current[:pause_stats_user] && args.last[:sql].include?('FROM "users"')

      Thread.current[:pause_stats_user] = false
      read_user.count_down
      raise 'sweep release timed out' unless release_sweep.wait(10)
    end
    ActiveSupport::Notifications.subscribed(observer, 'sql.active_record') do
      sweep = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          Thread.current[:pause_stats_user] = true
          Stats::BulkCalculator.new(user.id).call
        end
      end
      expect(read_user.wait(10)).to be(true)
      Stats::RefreshToponyms.new(user, 2014, 6).call
      release_sweep.count_down
      expect(sweep.join(10)).not_to be_nil
      sweep.value
    ensure
      release_sweep.count_down
      sweep&.join(10)
    end
    expect(Stats::CalculatingJob).to have_been_enqueued.with(user.id, recent.year, recent.month)
  ensure
    stat&.delete
  end
end
