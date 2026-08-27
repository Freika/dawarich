# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::RecoverPostIngestBatchesJob do
  let(:user) { create(:user) }

  it 'replays and clears pending post-ingest work' do
    batch = Points::PostIngestBatch.create!(
      user:,
      start_at: 1_700_000_000,
      end_at: 1_700_000_060
    )
    allow(Points::AnomalyFilterJob).to receive(:perform_later)
    allow_any_instance_of(Tracks::RealtimeDebouncer).to receive(:trigger)
    allow_any_instance_of(Tracks::BackfillScheduler).to receive(:call)
    allow_any_instance_of(Visits::RealtimeDebouncer).to receive(:trigger)

    expect { described_class.perform_now }.to change(Points::PostIngestBatch, :count).by(-1)
    expect(Points::AnomalyFilterJob).to have_received(:perform_later)
      .with(user.id, batch.start_at, batch.end_at)
  end
end
