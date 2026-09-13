# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TransportationModes::FleetReclassifyJob do
  let(:user) { create(:user) }

  it 'enqueues per-track jobs and re-enqueues itself with the cursor' do
    tracks = create_list(:track, 3, user: user)

    expect { described_class.perform_now }
      .to have_enqueued_job(TransportationModes::ReclassifyTrackJob).exactly(3).times
      .and have_enqueued_job(described_class).with(tracks.last.id)
  end

  it 'stops when no tracks remain beyond the cursor' do
    track = create(:track, user: user)

    expect { described_class.perform_now(track.id) }
      .not_to have_enqueued_job(described_class)
  end

  it 'runs on the low_priority queue' do
    expect(described_class.new.queue_name).to eq('low_priority')
  end
end
