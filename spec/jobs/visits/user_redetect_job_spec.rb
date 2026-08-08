# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::UserRedetectJob do
  let(:user) { create(:user) }
  let(:base_ts) { Time.zone.parse('2026-01-05 09:00:00 UTC').to_i }

  before do
    allow(DawarichSettings).to receive_messages(reverse_geocoding_enabled?: false, store_geodata?: false)
  end

  it 'redetects the user history and stamps visits_redetected_at' do
    6.times do |i|
      create(:point, user: user, latitude: 51.3402, longitude: 12.3712,
                     lonlat: 'POINT(12.3712 51.3402)', timestamp: base_ts + (i * 60), accuracy: 10)
    end

    described_class.perform_now(user.id)

    expect(user.visits.count).to eq(1)
    expect(user.reload.visits_redetected_at).to be_present
  end

  it 'quietly skips deleted users' do
    expect { described_class.perform_now(-1) }.not_to raise_error
  end

  it 'does not blow up the fleet when the per-user lock is busy' do
    allow(Tracks::PerUserLock).to receive(:with_user_lock)
      .and_raise(Tracks::PerUserLock::AcquisitionTimeout, 'busy')

    expect { described_class.perform_now(user.id) }.not_to raise_error
  end
end
