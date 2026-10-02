# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Imports::DestroyJob, type: :job do
  let!(:import) { create(:import, source: :gpx, status: :completed, skip_background_processing: true) }
  let(:job) { described_class.new }

  before { phoenix_tables! }

  it 'forwards a queued legacy deletion when native ownership has been claimed' do
    job_owner!('command:imports.destroy', :oban)
    job.perform(import.id)
    expect(Import.exists?(import.id)).to be true
    row = JobOutbox.pending.where(command_type: 'imports.destroy').sole
    expect(row.event_id).to eq(job.job_id)
    expect(row.payload).to eq('import_id' => import.id, 'user_id' => import.user_id)
    job.perform(import.id)
    expect(JobOutbox.where(command_type: 'imports.destroy').count).to eq(1)
  end

  it 'refuses an actor changed after canonical enqueue' do
    other = create(:user)
    expect { job.perform(import.id, expected_user_id: other.id) }.not_to(change { import.reload.status })
    expect(Import.exists?(import.id)).to be true
  end

  it 'does not cycle a durably handed back destruction into native ownership' do
    event = SecureRandom.uuid
    job_owner!('command:imports.destroy', :oban)
    ActiveRecord::Base.connection.execute(<<~SQL.squish)
      INSERT INTO phoenix.import_destroy_runs(import_id,user_id,event_id,native_fallback,phase)
      VALUES (#{import.id},#{import.user_id},'#{event}',true,'handback')
    SQL
    job.perform(import.id, expected_user_id: import.user_id, event_id: event)
    expect(Import.exists?(import.id)).to be false
    expect(JobOutbox.where(command_type: 'imports.destroy')).to be_empty
  end

  it 'refuses corrupted foreign-user import children before deleting' do
    point = create(:point, import:, user: create(:user))
    allow(Rails.logger).to receive(:warn)
    expect { job.perform(import.id) }.not_to(change { import.reload.status })
    expect(Point.exists?(point.id)).to be true
    expect(Rails.logger).to have_received(:warn)
      .with("[imports] import #{import.id} not deleted: it holds another user's data")
  end

  it 'skips a soft-deleted actor without restoring failed status' do
    import.user.update_column(:deleted_at, Time.current)
    expect { job.perform(import.id) }.not_to raise_error
    expect(import.reload.status).to eq('completed')
  end

  it 'joins the requested receipt when canonical pending destruction is rehomed' do
    event = SecureRandom.uuid
    job_owner!('command:imports.destroy', :oban)
    ActiveRecord::Base.connection.execute(<<~SQL.squish)
      INSERT INTO phoenix.import_destroy_runs(import_id,user_id,event_id)
      VALUES (#{import.id},#{import.user_id},'#{event}')
    SQL
    JobCommands.produce('imports.destroy', { 'import_id' => import.id, 'user_id' => import.user_id },
                        aggregate_id: import.id, producer: 'destruction regression')
    result = JobCommands.rehome!('imports.destroy', by: 'destruction regression')
    expect(result).to include(moved: 1, left: 0)
    queued = enqueued_jobs.find { |entry| entry[:job] == Imports::DestroyJob }
    arguments = ActiveJob::Arguments.deserialize(queued.fetch(:args))
    expect(arguments).to eq([import.id, { expected_user_id: import.user_id }])
    job.perform(arguments.first, **arguments.last)
    expect(Import.exists?(import.id)).to be false
    row = Imports::DestroyLegacy.receipt(import.id)
    expect(row).to include('event_id' => event, 'phase' => 'removed')
  end

  it 'retries a busy GPX destruction ten times, then marks the import failed with a clear message' do
    import.deleting!
    hold_import_lock("phoenix-import:#{import.id}") do
      perform_enqueued_jobs { described_class.perform_later(import.id) }
    end
    expect(performed_jobs.count { |entry| entry[:job] == described_class }).to eq(10)
    expect(import.reload).to have_attributes(status: 'failed', error_message: Imports::BusyRetry::MESSAGE)
  end

  it 'destroys a non-GPX import as before, without the session lock or a receipt' do
    csv = create(:import, source: :csv, status: :completed, skip_background_processing: true)
    hold_import_lock("phoenix-import:#{csv.id}") { described_class.perform_now(csv.id) }
    expect(Import.exists?(csv.id)).to be false
    expect(Imports::DestroyLegacy.receipt(csv.id)).to be_nil
  end

  it 'destroys a GPX import as before when Phoenix never migrated this database' do
    ActiveRecord::Base.connection.execute('DROP SCHEMA phoenix CASCADE')
    hold_import_lock("phoenix-import:#{import.id}") { described_class.perform_now(import.id) }
    expect(Import.exists?(import.id)).to be false
  end
end
