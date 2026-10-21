# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Achievements::BulkCommands' do
  it 'legacy bulk invocation forwards its keywords and pending command rehomes' do
    user = create(:user, status: :active)
    create(:point, user: user)
    JobOutbox.delete_all
    clear_enqueued_jobs
    job_owner!('command:achievements.bulk_check', :oban)
    job = Achievements::BulkCheckJob.new(notify: false, force: true, stale_only: true)
    options = { notify: false, force: true, stale_only: true }
    2.times { job.perform(**options) }
    expect(Achievements::CheckJob).not_to have_been_enqueued
    expect(JobOutbox.pending.sole).to have_attributes(
      command_type: 'achievements.bulk_check', payload: options.stringify_keys
    )
    due = 1.hour.from_now.change(usec: 0)
    JobOutbox.pending.sole.update!(scheduled_at: due)
    job_owner!('command:achievements.bulk_check', :sidekiq)
    JobCommands.rehome!('achievements.bulk_check', by: 'a12d2-spec')
    expect(Achievements::BulkCheckJob).to have_been_enqueued.with(**options).at(due)
    expect(JobOutbox.pending.count).to eq(0)
    clear_enqueued_jobs
    job_owner!('cron:achievements_bulk_check_job', :oban)
    job_owner!('command:achievements.bulk_check', :oban)
    Achievements::BulkCheckJob.new.perform('a12d2_cron')
    expect(JobOutbox.pending.count).to eq(0)
    expect(Achievements::CheckJob).not_to have_been_enqueued
    job.perform(**options)
    expect(JobOutbox.pending.sole.payload).to eq(options.stringify_keys)
    clear_enqueued_jobs
    job_owner!('command:achievements.bulk_check', :sidekiq)
    job.perform(**options)
    expect(Achievements::CheckJob).to have_been_enqueued.with(user.id, notify: false, force: true)
    clear_enqueued_jobs
    payload = { 'user_id' => user.id, 'notify' => false, 'run_at' => due.iso8601, 'event_id' => SecureRandom.uuid }
    handler = RailsCommands::Registry.handler('achievements.bulk_check_leaf')
    expect(handler).to be_present
    handler.call(payload)
    expect(Achievements::CheckJob).to have_been_enqueued.with(user.id, notify: false, force: false).at(due)
    clear_enqueued_jobs
    job_owner!('command:achievements.check', :oban)
    handler.call(payload)
    expect(JobOutbox.pending.find_by!(command_type: 'achievements.check')).to have_attributes(
      payload: { 'user_id' => user.id, 'notify' => false, 'oldest_timestamp' => nil }, scheduled_at: due
    )
    expect(Achievements::CheckJob).not_to have_been_enqueued
  end
end
