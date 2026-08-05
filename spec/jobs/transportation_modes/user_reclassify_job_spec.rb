# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TransportationModes::UserReclassifyJob do
  let(:user) { create(:user) }

  it 'starts progress tracking and fans out per-track jobs for the user only' do
    tracks = create_list(:track, 2, user: user)
    create(:track, user: create(:user))

    expect { described_class.perform_now(user.id) }
      .to have_enqueued_job(TransportationModes::ReclassifyTrackJob).exactly(2).times

    status = Tracks::TransportationRecalculationStatus.new(user.id)
    expect(status.in_progress?).to be true
    expect(status.data['total_tracks']).to eq(tracks.size)
  end

  it 'completes immediately for users without tracks' do
    described_class.perform_now(user.id)
    expect(Tracks::TransportationRecalculationStatus.new(user.id).current_status).to eq('completed')
  end

  it 'silently skips missing users' do
    expect { described_class.perform_now(-1) }.not_to raise_error
  end
end
