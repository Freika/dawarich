# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Imports::DestroyJob, type: :job do
  let!(:import) { create(:import, status: :completed, skip_background_processing: true) }
  let(:job) { described_class.new }

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
    expect { job.perform(import.id) }.not_to(change { import.reload.status })
    expect(Point.exists?(point.id)).to be true
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

  it 'retries a busy shared import lock without restoring failed status' do
    locked = Queue.new
    release = Queue.new
    contender = Thread.new do
      config = ActiveRecord::Base.connection_db_config.configuration_hash
      connection = PG.connect(host: config[:host], port: config[:port], user: config[:username],
                              password: config[:password], dbname: config[:database])
      key = "phoenix-import:#{import.id}"
      begin
        connection.exec_params('SELECT pg_advisory_lock(hashtextextended($1,0))', [key])
        locked << true
        release.pop
        connection.exec_params('SELECT pg_advisory_unlock(hashtextextended($1,0))', [key])
      ensure
        connection.finish
      end
    end
    locked.pop
    expect { job.perform(import.id) }.to raise_error(Imports::DestroyLegacy::Busy)
    expect(import.reload.status).to eq('completed')
  ensure
    release << true
    contender&.join
  end
end
