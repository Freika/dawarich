# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Queued transportation reclassification', type: :request do
  let(:user) { create(:user) }
  let(:progress) { Tracks::TransportationRecalculationStatus.new(user.id) }

  before do
    sign_in user
    clear_enqueued_jobs
  end

  def request_reclassification
    post tracks_recalculation_path, headers: { 'Accept' => 'text/vnd.turbo-stream.html' }
  end

  it 'enqueues once while the first fan-out is still waiting in the queue' do
    request_reclassification
    request_reclassification

    expect(TransportationModes::UserReclassifyJob).to have_been_enqueued.exactly(:once).with(user.id)
    expect(progress.in_progress?).to be true
    expect(progress.data).to include('status' => 'processing', 'total_tracks' => 0, 'processed_tracks' => 0)
    expect(response.body).to include('already running')
  end

  it 'keeps a waiting reservation when an older per-track job reports late progress' do
    request_reclassification
    progress.increment_processed!
    request_reclassification

    expect(progress.current_status).to eq('processing')
    expect(TransportationModes::UserReclassifyJob).to have_been_enqueued.exactly(:once).with(user.id)
  end

  it 'does not write late track progress into a waiting reservation' do
    request_reclassification
    before_progress = progress.data
    expect(progress).not_to receive(:update_progress)

    expect(progress.increment_processed!).to eq(0)
    expect(progress.data).to eq(before_progress)
  end

  it 'does not enqueue work when its reservation cannot be stored' do
    allow(Rails.cache).to receive(:write).and_call_original
    allow(Rails.cache).to receive(:write).with(progress.cache_key, anything, expires_in: anything).and_return(false)

    expect { request_reclassification }.to raise_error(IOError)
    expect(TransportationModes::UserReclassifyJob).not_to have_been_enqueued
  end

  it 'lets a completed run be requested again' do
    request_reclassification
    progress.start(total_tracks: 1)
    progress.complete
    request_reclassification

    expect(TransportationModes::UserReclassifyJob).to have_been_enqueued.exactly(:twice).with(user.id)
  end

  it 'releases a reservation after the enqueue adapter rejects the job' do
    adapter = ActiveJob::Base.queue_adapter
    allow(adapter).to receive(:enqueue).and_raise(ActiveJob::EnqueueError, 'synthetic enqueue failure')

    expect { request_reclassification }.to raise_error(ActiveJob::EnqueueError)
    expect(progress.in_progress?).to be false
    allow(adapter).to receive(:enqueue).and_call_original
    sign_in user
    request_reclassification

    expect(TransportationModes::UserReclassifyJob).to have_been_enqueued.exactly(:once).with(user.id)
  end

  it 'turns the queued reservation into ordinary progress when the worker starts' do
    request_reclassification
    TransportationModes::UserReclassifyJob.perform_now(user.id)

    expect(progress.current_status).to eq('completed')
    request_reclassification
    expect(TransportationModes::UserReclassifyJob).to have_been_enqueued.exactly(:twice).with(user.id)
  end
end
