# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Users::RecalculationCommands' do
  self.use_transactional_tests = false

  around do |example|
    connection = ActiveRecord::Base.connection
    sequence = connection.select_one('SELECT last_value, is_called FROM users_id_seq')
    example.run
  ensure
    connection.execute("SELECT setval('users_id_seq', #{sequence.fetch('last_value')}, " \
                       "#{connection.quote(sequence.fetch('is_called'))})")
  end

  before do
    phoenix_tables!
    @user = create(:user)
    @key = 'command:users.recalculate_data'
    job_owner!(@key, :sidekiq)
    job_owner!('command:achievements.check', :sidekiq)
    clear_enqueued_jobs
  end

  after do
    JobOutbox.where(command_type: 'users.recalculate_data', aggregate_id: @user.id).delete_all
    connection = ActiveRecord::Base.connection
    connection.execute('DELETE FROM phoenix.rails_commands ' \
                       "WHERE kind IN ('users.recalculate_data','achievements.check') " \
                       "AND payload->>'user_id'=#{connection.quote(@user.id.to_s)}")
    connection.execute("DELETE FROM phoenix.job_owners WHERE key=#{connection.quote(@key)}")
    connection.execute("DELETE FROM phoenix.job_owners WHERE key='command:achievements.check'")
    User.unscoped.where(id: @user.id).delete_all
    clear_enqueued_jobs
  end

  it 'user rebuild producer and reverse handler enqueue complete source jobs by current owner' do
    payload = {
      'user_id' => @user.id, 'year' => 2025, 'notify' => false, 'job_queue' => 'low_priority',
      'source_job_id' => SecureRandom.uuid, 'ambient_zone' => 'Asia/Tokyo'
    }
    due = Time.current.change(usec: 0) + 60
    expect(Users::RecalculationCommands.normalize(payload.merge('year' => '2025tail', 'notify' => '')))
      .to eq(payload.merge('notify' => true))
    expect(Users::RecalculationCommands.normalize(payload.merge('year' => 2025.9, 'notify' => nil)))
      .to eq(payload)
    JobCommands.produce('users.recalculate_data', payload, aggregate_id: @user.id,
                        producer: 'spec', scheduled_at: due)
    queued = enqueued_jobs.sole.deep_dup
    expect(queued.fetch('job_id')).to eq(payload['source_job_id'])
    expect(queued.fetch('timezone')).to eq('Asia/Tokyo')
    expect(queued.fetch('arguments')).to eq(
      [@user.id, { 'year' => 2025, 'notify' => false, 'job_queue' => 'low_priority',
                  '_aj_ruby2_keywords' => %w[year notify job_queue] }]
    )
    expect(Time.iso8601(queued.fetch('scheduled_at'))).to eq(due)
    clear_enqueued_jobs
    job_owner!(@key, :oban)
    ActiveJob::Base.deserialize(queued).perform_now
    row = JobOutbox.where(command_type: 'users.recalculate_data', aggregate_id: @user.id).sole
    expect(row).to have_attributes(event_id: payload['source_job_id'], payload:, scheduled_at: due)
    expect(enqueued_jobs).to be_empty
    JobOutbox.where(event_id: row.event_id).delete_all

    reverse = payload.merge('run_at' => due.to_i)
    connection = ActiveRecord::Base.connection
    statement = 'INSERT INTO phoenix.rails_commands (kind,payload) VALUES (?,?::jsonb)'
    connection.execute(ActiveRecord::Base.sanitize_sql_array([statement, 'users.recalculate_data', reverse.to_json]))
    expect(RailsCommands::Poller.drain_once).to be >= 1
    expect(JobOutbox.where(command_type: 'users.recalculate_data', aggregate_id: @user.id).sole.payload).to eq(payload)
    expect(enqueued_jobs).to be_empty
    expect(JobCommands.rehome!('users.recalculate_data', by: 'spec')).to eq(moved: 1, left: 0)
    expect(enqueued_jobs.sole.fetch('job_id')).to eq(payload['source_job_id'])
    clear_enqueued_jobs
    connection.execute(ActiveRecord::Base.sanitize_sql_array([statement, 'users.recalculate_data', reverse.to_json]))
    RailsCommands::Poller.drain_once
    expect(enqueued_jobs.sole.fetch('job_id')).to eq(payload['source_job_id'])
    expect(enqueued_jobs.sole.fetch('arguments')).to eq(queued.fetch('arguments'))
    expect(enqueued_jobs.sole.fetch('timezone')).to eq('Asia/Tokyo')
    expect(JobOutbox.where(command_type: 'users.recalculate_data', aggregate_id: @user.id)).to be_empty

    clear_enqueued_jobs
    corpus = JSON.parse(File.read(Rails.root.join('app-phoenix/test/fixtures/a12d1b3/recalculations.json')))
                 .fetch('cases').find { _1.fetch('id') == 'backfill_async' }
    rebuild_id = Digest::UUID.uuid_v5(Digest::UUID::URL_NAMESPACE,
                                      "anomaly_backfill.rebuild:#{corpus.fetch('job').fetch('job_id')}")
    reset_payload = {
      'user_id' => @user.id, 'year' => nil, 'notify' => true, 'job_queue' => nil,
      'source_job_id' => rebuild_id,
      'ambient_zone' => corpus.fetch('job').fetch('timezone'), 'run_at' => due.to_i
    }
    achievement = { 'user_id' => @user.id, 'notify' => true, 'oldest_timestamp' => 1_735_687_800,
                    'run_at' => due.to_i }
    connection.execute(ActiveRecord::Base.sanitize_sql_array(
                         [statement, 'users.recalculate_data', reset_payload.to_json]
                       ))
    connection.execute(ActiveRecord::Base.sanitize_sql_array(
                         [statement, 'achievements.check', achievement.to_json]
                       ))
    RailsCommands::Poller.drain_once
    rebuilt = enqueued_jobs.find { _1.fetch('job_class') == 'Users::RecalculateDataJob' }
    checked = enqueued_jobs.find { _1.fetch('job_class') == 'Achievements::CheckJob' }
    expect(rebuilt.fetch('job_id')).to eq(reset_payload.fetch('source_job_id'))
    expect(rebuilt.fetch('timezone')).to eq(reset_payload.fetch('ambient_zone'))
    expect(rebuilt.fetch('arguments')).to eq(
      [@user.id, { 'year' => nil, 'notify' => true, 'job_queue' => nil,
                  '_aj_ruby2_keywords' => %w[year notify job_queue] }]
    )
    expect(checked).not_to be_nil
    expect(checked.fetch('arguments')).to eq(
      [@user.id, { 'notify' => true, 'oldest_timestamp' => 1_735_687_800,
                  '_aj_ruby2_keywords' => %w[notify oldest_timestamp] }]
    )
  end
end
