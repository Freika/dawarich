# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Cache command routing' do
  include ActiveSupport::Testing::TimeHelpers
  self.use_transactional_tests = false

  around do |example|
    phoenix_tables!
    connection = ActiveRecord::Base.connection
    sequences = %w[users_id_seq stats_id_seq digests_id_seq phoenix.rails_commands_id_seq].index_with do |sequence|
      connection.select_one("SELECT last_value, is_called FROM #{sequence}")
    end
    example.run
  ensure
    [Users::Digest, Stat].each { |model| model.where(user_id: 180_101).delete_all }
    User.unscoped.where(id: 180_101).delete_all
    JobOutbox.where(command_type: 'cache.preheat_user', aggregate_id: 180_101).delete_all
    connection.execute("DELETE FROM phoenix.rails_commands WHERE kind IN ('cache.preheat_user','cache.preheat_sweep')")
    connection.execute('DELETE FROM phoenix.job_owners ' \
                       "WHERE key IN ('command:cache.preheat_user','cron:cache_preheating_job')")
    sequences&.each do |sequence, state|
      connection.execute("SELECT setval('#{sequence}', #{state.fetch('last_value')}, " \
                         "#{connection.quote(state.fetch('is_called'))})")
    end
    clear_enqueued_jobs
  end

  it 'pending rehome reclaim and forward retain the same source job UUID zone and due time' do
    travel_to(Time.utc(2026, 10, 3, 12)) do
      User.insert_all!([{ id: 180_101, email: 'cache-command@example.invalid', encrypted_password: '', status: 1,
                         settings: { 'timezone' => 'Europe/Berlin' }, plan: 1,
                         created_at: Time.current, updated_at: Time.current }])
      Stat.insert_all!([{ id: 180_501, user_id: 180_101, year: 2025, month: 1, distance: 1000,
                         daily_distance: {}, toponyms: [], created_at: Time.current, updated_at: Time.current }])
      source = SecureRandom.uuid
      payload = { 'user_id' => 180_101, 'time_zone' => 'Asia/Tokyo', 'source_job_id' => source }
      due = Time.current + 3600
      job_owner!('command:cache.preheat_user', :oban)
      expect(JobCommands.produce('cache.preheat_user', payload, aggregate_id: 180_101,
                                 producer: 'spec', scheduled_at: due)).to eq(:outbox)
      expect(JobOutbox.find(source)).to have_attributes(payload:, command_version: 1, scheduled_at: due)
      expect(JobCommands.rehome!('cache.preheat_user', by: 'spec')).to eq(moved: 1, left: 0)
      queued = enqueued_jobs.sole.deep_dup
      expect(queued.fetch('job_id')).to eq(source)
      expect(queued.fetch('timezone')).to eq('Asia/Tokyo')
      expect(Time.iso8601(queued.fetch('scheduled_at'))).to eq(due)
      expect(JobOutbox.exists?(source)).to be(false)
      clear_enqueued_jobs
      job_owner!('command:cache.preheat_user', :oban)
      job = ActiveJob::Base.deserialize(queued)
      job.perform_now
      job.perform_now
      expect(JobOutbox.where(command_type: 'cache.preheat_user', aggregate_id: 180_101).count).to eq(1)
      expect(JobOutbox.find(source)).to have_attributes(payload:, scheduled_at: due, state: 'pending')
      JobOutbox.find(source).update!(state: 'dispatched')
      insert = ['INSERT INTO phoenix.rails_commands(kind,payload) VALUES (?,?::jsonb)',
                'cache.preheat_user', payload.merge('run_at' => due.to_i).to_json]
      sql = ActiveRecord::Base.sanitize_sql_array(insert)
      ActiveRecord::Base.connection.execute(sql)
      expect(RailsCommands::Poller.drain_once).to eq(1)
      reverse = enqueued_jobs.sole
      expect(reverse.fetch('job_id')).to eq(source)
      expect(reverse.fetch('timezone')).to eq('Asia/Tokyo')
      expect(Time.iso8601(reverse.fetch('scheduled_at'))).to eq(due)
      ActiveJob::Base.deserialize(reverse).perform_now
      expect(JobOutbox.find(source).state).to eq('dispatched')
    end
  end
end
