# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'public.job_outbox' do
  let(:connection) { ActiveRecord::Base.connection }

  def insert(overrides = {})
    row = {
      event_id: SecureRandom.uuid, command_type: 'trips.calculate', command_version: 1,
      payload: { 'trip_id' => 1 }.to_json, scheduled_at: Time.current.utc.iso8601(6),
      state: 'pending', dedupe_key: nil
    }.merge(overrides)
    connection.execute(ActiveRecord::Base.sanitize_sql_array([<<~SQL.squish, row]))
      INSERT INTO job_outbox (event_id, command_type, command_version, payload, scheduled_at, state, dedupe_key)
      VALUES (:event_id, :command_type, :command_version, CAST(:payload AS jsonb),
              CAST(:scheduled_at AS timestamptz), :state, :dedupe_key)
    SQL
  end

  def rejection(overrides)
    ActiveRecord::Base.transaction(requires_new: true) { insert(overrides) }
    nil
  rescue ActiveRecord::StatementInvalid => e
    e.message
  end

  it 'accepts a well-formed pending command with defaults' do
    insert
    row = connection.select_one('SELECT state, metadata::text AS metadata, created_at FROM job_outbox')

    expect(row['state']).to eq('pending')
    expect(row['metadata']).to eq('{}')
    expect(row['created_at']).to be_present
  end

  it 'rejects an unknown state, a non-positive version, a non-object payload and an oversized payload' do
    expect(rejection(state: 'done')).to include('job_outbox_state_known')
    expect(rejection(command_version: 0)).to include('job_outbox_command_version_positive')
    expect(rejection(payload: [1].to_json)).to include('job_outbox_payload_object')
    expect(rejection(payload: { 'x' => 'a' * 9000 }.to_json)).to include('job_outbox_payload_object')
  end

  it 'allows one pending command per dedupe key, and any number once dispatched' do
    insert(dedupe_key: '7')

    expect(rejection(dedupe_key: '7')).to include('index_job_outbox_on_pending_dedupe')
    expect(rejection(dedupe_key: '7', state: 'dispatched')).to be_nil
    expect(rejection(dedupe_key: nil)).to be_nil
    expect(rejection(dedupe_key: nil)).to be_nil
  end

  it 'indexes only pending rows for the relay' do
    definition = connection.select_value("SELECT indexdef FROM pg_indexes WHERE indexname = 'index_job_outbox_on_due'")

    expect(definition).to include('(scheduled_at, event_id)').and include("'pending'")
  end
end
