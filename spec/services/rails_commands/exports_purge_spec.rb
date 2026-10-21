# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Exports purge follow up' do
  include ActiveJob::TestHelper

  it 'deleted export follow up preserves surviving blob references and purges detached files' do
    user = create(:user)
    export = user.exports.create!(name: 'Synthetic', status: :completed, file_type: :user_data, file_format: :archive)
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new('synthetic'), filename: 'export.zip')
    export.file.attach(blob)
    payload = { 'export_id' => export.id, 'user_id' => user.id, 'blob_ids' => [blob.id] }
    handler = RailsCommands::Registry.handler('exports.purge')
    expect(handler).to be_present
    clear_enqueued_jobs
    handler.call(payload)
    expect(enqueued_jobs).to be_empty
    export.file.detach
    export.delete
    other = user.exports.create!(name: 'Surviving', status: :completed, file_type: :user_data, file_format: :archive)
    other.file.attach(blob)
    clear_enqueued_jobs
    handler.call(payload)
    expect(enqueued_jobs).to be_empty
    other.file.detach
    expect { handler.call(payload) }.to have_enqueued_job(ActiveStorage::PurgeJob).with(blob)
    perform_enqueued_jobs(only: ActiveStorage::PurgeJob)
    expect(ActiveStorage::Blob.exists?(blob.id)).to be(false)
    expect { handler.call(payload) }.not_to have_enqueued_job
  end
end
