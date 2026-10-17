# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Posters purge follow up' do
  include ActiveJob::TestHelper

  it 'deleted poster follow up is harmless and purge checks surviving blob references' do
    user = create(:user)
    poster = user.posters.create!(name: 'Synthetic')
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new('synthetic'), filename: 'poster.png')
    poster.image.attach(blob)
    payload = { 'poster_id' => poster.id, 'user_id' => user.id, 'blob_ids' => [blob.id] }
    handler = RailsCommands::Registry.handler('posters.purge')
    expect(handler).to be_present
    clear_enqueued_jobs
    handler.call(payload)
    expect(enqueued_jobs).to be_empty
    poster.image.detach
    poster.delete
    other = user.posters.create!(name: 'Surviving reference')
    other.image.attach(blob)
    clear_enqueued_jobs
    handler.call(payload)
    expect(enqueued_jobs).to be_empty
    expect(blob.reload).to be_present
    other.image.detach
    expect { handler.call(payload) }.to have_enqueued_job(ActiveStorage::PurgeJob).with(blob)
    perform_enqueued_jobs(only: ActiveStorage::PurgeJob)
    expect { handler.call(payload) }.not_to have_enqueued_job
    expect(ActiveStorage::Blob.exists?(blob.id)).to be(false)
  end
end
