# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Imports schedule track generation for the imported point range' do
  let(:user) { create(:user) }
  let(:import) { create(:import, source: 'owntracks', status: 'created', user: user) }
  let(:file_path) { Rails.root.join('spec/fixtures/files/owntracks/2024-03.rec') }
  let(:service) { Imports::Create.new(user, import) }

  before do
    import.file.attach(
      io: File.open(file_path),
      filename: '2024-03.rec',
      content_type: 'application/octet-stream'
    )
  end

  it 'enqueues a parallel track generation job covering the imported range' do
    Sidekiq::Testing.inline! do
      expect { service.call }.to have_enqueued_job(Tracks::ParallelGeneratorJob)
    end
  end

  it 'covers exactly the timestamp range of imported points' do
    service.call

    min_ts, max_ts = import.reload.points.pick('MIN(timestamp), MAX(timestamp)')

    expect(Tracks::ParallelGeneratorJob).to have_been_enqueued.with(
      user.id,
      start_at: Time.zone.at(min_ts),
      end_at: Time.zone.at(max_ts),
      mode: 'bulk'
    )
  end

  context 'when the import produced no points' do
    it 'does not enqueue a track generation job' do
      allow_any_instance_of(OwnTracks::Importer).to receive(:call) # no-op importer
      expect { service.call }.not_to have_enqueued_job(Tracks::ParallelGeneratorJob)
    end
  end
end
