# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Imports download command handoff' do
  let!(:import) { create(:import, skip_background_processing: true) }
  let(:payload) { { 'import_id' => import.id, 'user_id' => import.user_id, 'source_blob_id' => import.file.blob_id } }

  before do
    phoenix_tables!
    import.file.attach(io: StringIO.new('<gpx/>'), filename: 'original.gpx')
  end

  it 'forwards a previously queued legacy job after Oban claims the lane' do
    job_owner!('command:imports.prepare_download', :oban)
    Imports::PrepareDownloadJob.perform_now(import.id, import.file.blob_id)
    expect(JobOutbox.pending.sole.payload).to eq(payload)
    expect(JobOutbox.pending.sole.command_type).to eq('imports.prepare_download')
    expect(import.reload.prepared_download).not_to be_attached
  end

  it 'honours an explicit admission fallback after ownership is restored' do
    job_owner!('command:imports.prepare_download', :oban)
    Imports::PrepareDownloadJob.perform_now(import.id, import.file.blob_id, native_fallback: true)
    expect(JobOutbox.count).to eq(0)
  end

  it 'dispatches native handback using the actual job and fallback flag' do
    expect { RailsCommands::Registry.handler('imports.prepare_download').call(payload.merge('native_fallback' => true)) }
      .to have_enqueued_job(Imports::PrepareDownloadJob).with(import.id, import.file.blob_id, native_fallback: true,
expected_user_id: import.user_id)
  end

  it 'rejects foreign user and stale source from reverse dispatch' do
    expect { RailsCommands::Registry.handler('imports.prepare_download').call(payload.merge('user_id' => import.user_id + 999)) }
      .not_to have_enqueued_job(Imports::PrepareDownloadJob)
    expect { RailsCommands::Registry.handler('imports.prepare_download').call(payload.merge('source_blob_id' => import.file.blob_id + 999)) }
      .not_to have_enqueued_job(Imports::PrepareDownloadJob)
  end
  it 'retains the queued actor instead of preparing another owner after reassignment' do
    original_user = import.user_id
    import.update!(user: create(:user))
    Imports::PrepareDownloadJob.perform_now(import.id, import.file.blob_id,
                                            native_fallback: true, expected_user_id: original_user)
    expect(import.reload.prepared_download).not_to be_attached
    expect(JobOutbox.count).to eq(0)
  end
end
