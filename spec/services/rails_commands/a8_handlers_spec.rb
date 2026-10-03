# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'RailsCommands::A8Handlers' do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }

  def detached_payload(video)
    attachment = video.file.attachment
    { 'user_id' => video.user_id, 'blob_id' => attachment.blob_id, 'action' => 'purge_detached',
      'attachment' => attachment.attributes.slice('id', 'name', 'record_type', 'record_id', 'blob_id') }
  end

  it 'attachment shim retains a blob referenced by another record' do
    first = create(:route_video, :with_file, user:)
    blob = first.file.blob
    second = create(:route_video, user:)
    second.file.attach(blob)
    payload = detached_payload(first)
    first.file.attachment.delete
    first.update!(status: :expired)
    clear_enqueued_jobs

    RailsCommands::Registry.handler('route_videos.attachment_job').call(payload)

    expect(blob.reload.attachments.pluck(:record_id)).to eq([second.id])
    expect(enqueued_jobs).to be_empty
    second.file.attachment.delete
    expect { RailsCommands::A8Handlers.attachment_job(payload) }.to have_enqueued_job(ActiveStorage::PurgeJob).with(blob)
    perform_enqueued_jobs(only: ActiveStorage::PurgeJob)
    expect(ActiveStorage::Blob.exists?(blob.id)).to be(false)
    clear_enqueued_jobs
    RailsCommands::A8Handlers.attachment_job(payload)
    expect(enqueued_jobs).to be_empty
  end

  it 'attachment shim refuses invalid identity and purges only unattached rejection blobs' do
    video = create(:route_video, :with_file, user:)
    blob = video.file.blob
    payload = detached_payload(video)
    clear_enqueued_jobs
    RailsCommands::A8Handlers.attachment_job(payload)
    video.file.attachment.delete
    RailsCommands::A8Handlers.attachment_job(payload.deep_merge('attachment' => { 'blob_id' => blob.id + 1 }))
    RailsCommands::A8Handlers.attachment_job(payload.merge('user_id' => user.id + 1))
    RailsCommands::A8Handlers.attachment_job(payload.merge('action' => 'anything'))
    expect(enqueued_jobs).to be_empty
    expect(blob.reload).to be_present
    expect do
      RailsCommands::A8Handlers.attachment_job('user_id' => user.id, 'blob_id' => blob.id,
                                               'action' => 'purge_unattached')
    end
      .to have_enqueued_job(ActiveStorage::PurgeJob).with(blob)
  end

  it 'redetection shim delegates to the existing job without stamping cooldown' do
    user.update_columns(visits_redetected_at: nil)
    clear_enqueued_jobs
    expect { RailsCommands::Registry.handler('visits.web_redetect').call('user_id' => user.id) }
      .to have_enqueued_job(Visits::FullHistoryRedetectJob).with(user.id)
    expect(user.reload.visits_redetected_at).to be_nil
  end
end
