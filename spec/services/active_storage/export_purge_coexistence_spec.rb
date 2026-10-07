# frozen_string_literal: true

require 'rails_helper'
require 'stringio'

RSpec.describe 'R1 Rails-owned export purge', type: :job do
  it 'R1 preserves original ActiveStorage target loss for both export generations after failed storage deletion' do
    adapter = ActiveJob::QueueAdapters::TestAdapter.new
    allow(ActiveStorage::PurgeJob).to receive(:queue_adapter).and_return(adapter)
    allow(ActiveStorage::PurgeJob).to receive(:enqueue_after_transaction_commit).and_return(false)
    original_inline = ActiveSupport::IsolatedExecutionState[:job_commands_inline]
    ActiveSupport::IsolatedExecutionState[:job_commands_inline] = true

    %w[original exports.purge].each do |kind|
      blobs = 2.times.map do
        ActiveStorage::Blob.create_and_upload!(io: StringIO.new('synthetic export generation'),
                                               filename: 'synthetic.zip', content_type: 'application/zip',
                                               service_name: 'test')
      end
      payload = { 'export_id' => 9_999_999_999, 'blob_ids' => blobs.map(&:id) }
      adapter.enqueued_jobs.clear
      if kind == 'original'
        blobs.each(&:purge_later)
      else
        RailsCommands::Registry.handler(kind).call(payload)
      end
      jobs = adapter.enqueued_jobs.dup
      expect(jobs.length).to eq(2)
      jobs.zip(blobs).each do |serialized, blob|
        path = blob.service.send(:path_for, blob.key)
        begin
          File.delete(path)
          Dir.mkdir(path)
          expect { ActiveJob::Base.execute(serialized) }.to raise_error(Errno::EPERM)
          expect(ActiveStorage::Blob.exists?(blob.id)).to be(false)
          Dir.rmdir(path)
          File.write(path, 'synthetic export generation')
          expect { ActiveJob::Base.execute(serialized) }.not_to raise_error
          expect(File.exist?(path)).to be(true)
        ensure
          File.delete(path) if File.file?(path)
          Dir.rmdir(path) if File.directory?(path)
        end
      end
      next if kind == 'original'

      count = adapter.enqueued_jobs.size
      RailsCommands::Registry.handler(kind).call(payload)
      expect(adapter.enqueued_jobs.size).to eq(count)
    end
  ensure
    ActiveSupport::IsolatedExecutionState[:job_commands_inline] = original_inline
  end
end
