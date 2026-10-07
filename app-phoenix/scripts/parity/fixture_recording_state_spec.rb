# frozen_string_literal: true

require 'rails_helper'
require_relative 'places_closure_capture'

RSpec.describe FixtureRecording do
  it 'pins cleanup-task batch ordering while preserving every user and staggered delay' do
    3.times { create(:user) }
    ids = User.order(:id).pluck(:id)
    allow_any_instance_of(ActiveRecord::Batches::BatchEnumerator).to receive(:each)
      .and_yield(User.order(id: :desc))
    due = []
    allow(Places::OrphanCleanupJob).to receive(:set) do |wait:|
      instance_double(ActiveJob::ConfiguredJob).tap do |job|
        allow(job).to receive(:perform_later) { |uid| due << { user_id: uid, delay: wait.to_f } }
      end
    end
    task = Rake::Task['dawarich:cleanup_suggested_places']
    task.reenable
    capture_cleanup_task(task)
    expect(due).to eq(ids.each_with_index.map { |id, index| { user_id: id, delay: index * 0.1 } })
  end

  it 'pins initial wrapped-import blob and attachment IDs and restores ambient sequence state' do
    connection = ActiveRecord::Base.connection
    tables = %w[active_storage_blobs active_storage_attachments]
    sequences = tables.map { connection.select_value("SELECT pg_get_serial_sequence('#{_1}', 'id')") }
    original = sequences.map { connection.select_one("SELECT last_value, is_called FROM #{_1}") }
    user = create(:user)
    import = Import.new(user:, name: 'wrapped.gpx.zip', source: :gpx, status: :completed)
    import.skip_background_processing = true
    import.save!(validate: false)
    captures = [true, false].map do |called|
      sequences.each { connection.execute("SELECT setval('#{_1}', 9900000, #{called})") }
      ambient = sequences.map { connection.select_one("SELECT last_value, is_called FROM #{_1}") }
      ids = described_class.with_sequences(tables.index_with { 9_800_000 }) do
        connection.transaction(requires_new: true) do
          import.reload
          blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new('PK'), filename: 'wrapped.gpx.zip',
                                                        content_type: 'application/zip')
          import.file.attach(blob)
          result = [blob.id, import.file.attachment.id]
          expect(result).to eq([9_800_000, 9_800_000])
          raise ActiveRecord::Rollback, result.inspect
        ensure
          @recorded_ids = result
        end
        @recorded_ids
      end
      expect(sequences.map { connection.select_one("SELECT last_value, is_called FROM #{_1}") }).to eq(ambient)
      ids
    end
    expect(captures.uniq).to eq([[9_800_000, 9_800_000]])
    expect do
      described_class.with_sequences(tables.index_with { 9_800_000 }) { raise 'recording failed' }
    end.to raise_error('recording failed')
    expect(sequences.map { connection.select_one("SELECT last_value, is_called FROM #{_1}") })
      .to eq(tables.map { { 'last_value' => 9_900_000, 'is_called' => false } })
  ensure
    sequences&.zip(original || [])&.each do |sequence, state|
      connection.execute("SELECT setval('#{sequence}', #{state.fetch('last_value')}, #{state.fetch('is_called')})")
    end
  end

  it 'isolates routing-error ActionCable diagnostics after subscriber initialization and restores the subscriber' do
    server = ActionCable.server
    subscriber = server.pubsub
    event_loop = server.event_loop
    described_class.with_clean_cable_state do
      %i[@pubsub @event_loop @remote_connections @worker_pool].each do |key|
        expect(server.instance_variable_get(key)).to be_nil
      end
      expect(server.inspect).to include('@pubsub=nil')
    end
    expect(server.pubsub).to equal(subscriber)
    expect(server.event_loop).to equal(event_loop)
    expect do
      described_class.with_clean_cable_state { raise 'recording failed' }
    end.to raise_error('recording failed')
    expect(server.pubsub).to equal(subscriber)
    expect(server.event_loop).to equal(event_loop)
  end
end
