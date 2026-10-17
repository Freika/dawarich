# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Point export command time zone' do
  let(:user) { create(:user) }

  %w[America/New_York UTC Berlin Asia/Tokyo].each do |zone|
    it "captures the same zone as the Sidekiq job for #{zone}" do
      Time.use_zone(zone) do
        create(:export, user:, name: 'sidekiq.gpx', file_format: :gpx)
      end
      legacy_zone = enqueued_jobs.sole.fetch('timezone')
      clear_enqueued_jobs
      job_owner!('command:exports.points', :oban)

      export = Time.use_zone(zone) { create(:export, user:, name: 'oban.gpx', file_format: :gpx) }

      expect(JobOutbox.sole).to have_attributes(
        command_version: 2,
        payload: { 'export_id' => export.id, 'user_id' => user.id, 'time_zone' => legacy_zone }
      )
      expect(enqueued_jobs).to be_empty
    end
  end

  { nil => 'UTC', 'Not/AZone' => 'Europe/Berlin' }.each do |stored_zone, want|
    it "keeps the Rails handler fallback for stored zone #{stored_zone.inspect}" do
      user.update_columns(settings: user.settings.merge('timezone' => stored_zone))
      Export.insert_all([{ user_id: user.id, name: 'handler.gpx', status: 0, file_format: 1, file_type: 0,
                           created_at: Time.current, updated_at: Time.current }])
      export = user.exports.sole
      payload = { 'export_id' => export.id, 'user_id' => user.id, 'locale' => 'en' }
      handler = RailsCommands::Registry.handler('exports.points_created')

      Time.use_zone('Europe/Berlin') { handler.call(payload) }
      expect(enqueued_jobs.sole.fetch('timezone')).to eq(want)
      clear_enqueued_jobs
      job_owner!('command:exports.points', :oban)
      Time.use_zone('Europe/Berlin') { handler.call(payload) }

      expect(JobOutbox.sole.payload.fetch('time_zone')).to eq(want)
    end
  end

  it 'does not replace the captured zone when forwarding from another zone' do
    payload = { 'export_id' => 11, 'user_id' => user.id, 'time_zone' => 'America/New_York' }
    Time.use_zone('Asia/Tokyo') do
      JobCommands.forward('exports.points', payload, event_id: SecureRandom.uuid, aggregate_id: 11,
                                                     producer: 'spec')
    end

    expect(JobOutbox.sole).to have_attributes(command_version: 2, payload:)
  end

  it 'rehome drains old and new versions and preserves the captured zone' do
    job_owner!('command:exports.points', :oban)
    [{ 'export_id' => 11, 'user_id' => user.id },
     { 'export_id' => 12, 'user_id' => user.id, 'time_zone' => 'America/New_York' }].each_with_index do |payload, n|
      JobOutbox.create!(event_id: SecureRandom.uuid, command_type: 'exports.points', command_version: n + 1,
                        payload:, aggregate_id: payload.fetch('export_id'), scheduled_at: Time.current)
    end

    result = Time.use_zone('Europe/Berlin') { JobCommands.rehome!('exports.points', by: 'spec') }

    expect(result).to eq(moved: 2, left: 0)
    expect(JobOutbox.count).to eq(0)
    expect(enqueued_jobs.map { |job| [job[:args].first, job.fetch('timezone')] })
      .to contain_exactly([11, 'Europe/Berlin'], [12, 'America/New_York'])
  end

  it 'applies the captured zone inside the after-commit enqueue' do
    payload = { 'export_id' => 11, 'user_id' => user.id, 'time_zone' => 'America/New_York' }

    ActiveRecord::Base.transaction do
      Time.use_zone('Asia/Tokyo') do
        JobCommands::COMMANDS.fetch('exports.points').fetch(:sidekiq).call(payload, Time.current)
      end
    end

    expect(enqueued_jobs.sole.fetch('timezone')).to eq('America/New_York')
  end
end
