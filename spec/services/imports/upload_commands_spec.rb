# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Imports::UploadCommands do
  let(:user) { create(:user) }
  let(:import) { create(:import, user:, source: :gpx, skip_background_processing: true) }
  let(:payload) { { 'import_id' => import.id, 'user_id' => user.id, 'time_zone' => 'Pacific/Auckland' } }

  it 'enqueues the real Rails job in the captured upload zone' do
    expect { described_class.call(payload) }.to have_enqueued_job(Import::ProcessJob).with(import.id)
    job = ActiveJob::Base.queue_adapter.enqueued_jobs.last
    expect(job.fetch(:job)).to eq(Import::ProcessJob)
    expect(job.fetch('timezone')).to eq('Pacific/Auckland')
    expect(job.fetch('locale')).to eq(user.locale.to_s)
  end

  it 'ignores deleted, completed and cross-user imports' do
    expect { described_class.call(payload.merge('user_id' => user.id + 1)) }.not_to have_enqueued_job
    import.update!(status: :completed)
    expect { described_class.call(payload) }.not_to have_enqueued_job
    import.update!(status: :deleting)
    expect { described_class.call(payload) }.not_to have_enqueued_job
  end
end
