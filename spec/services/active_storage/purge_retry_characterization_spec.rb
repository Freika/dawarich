# frozen_string_literal: true

require 'rails_helper'
require 'stringio'

RSpec.describe 'F3 original Rails serialized purge retry', type: :job do
  it 'characterizes target loss in the original job and every Rails-owned media hand-back' do
    original_inline = ActiveSupport::IsolatedExecutionState[:job_commands_inline]
    allow(ActiveStorage::PurgeJob).to receive(:queue_adapter).and_return(ActiveJob::QueueAdapters::TestAdapter.new)
    allow(ActiveStorage::PurgeJob).to receive(:enqueue_after_transaction_commit).and_return(false)
    ActiveSupport::IsolatedExecutionState[:job_commands_inline] = true

    ['original', 'posters.purge', 'exports.purge', 'route_videos.attachment_job'].each do |kind|
      path = nil
      begin
        adapter = ActiveStorage::PurgeJob.queue_adapter
        adapter.enqueued_jobs.clear
        blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new('synthetic media'),
                                                      filename: 'synthetic.txt', content_type: 'text/plain',
                                                      service_name: 'test')
        payload = { 'user_id' => 9_999_999_999, 'blob_ids' => [blob.id], 'poster_id' => 9_999_999_999,
                    'export_id' => 9_999_999_999, 'blob_id' => blob.id, 'action' => 'purge_unattached' }
        if kind == 'original'
          blob.purge_later
        else
          RailsCommands::Registry.handler(kind).call(payload)
        end
        serialized = adapter.enqueued_jobs.last
        expect(serialized.fetch('job_class')).to eq('ActiveStorage::PurgeJob')
        path = blob.service.send(:path_for, blob.key)
        File.delete(path)
        Dir.mkdir(path)
        expect { ActiveJob::Base.execute(serialized) }.to raise_error(Errno::EPERM)
        expect(ActiveStorage::Blob.exists?(blob.id)).to be(false)
        Dir.rmdir(path)
        File.write(path, 'synthetic media')
        expect { ActiveJob::Base.execute(serialized) }.not_to raise_error
        expect(File.exist?(path)).to be(true)
        next if kind == 'original'

        count = adapter.enqueued_jobs.size
        RailsCommands::Registry.handler(kind).call(payload)
        expect(adapter.enqueued_jobs.size).to eq(count)
      ensure
        File.delete(path) if path && File.file?(path)
        Dir.rmdir(path) if path && File.directory?(path)
      end
    end
  ensure
    ActiveSupport::IsolatedExecutionState[:job_commands_inline] = original_inline
  end
end
