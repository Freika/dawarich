# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TransportationModes::UserReclassifyJob do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }

  it 'starts progress tracking and fans out per-track jobs for the user only' do
    tracks = create_list(:track, 101, user: user)
    create(:track, user: create(:user))

    freeze_time do
      expect { described_class.perform_now(user.id) }
        .to have_enqueued_job(TransportationModes::ReclassifyTrackJob).exactly(101).times
      jobs = enqueued_jobs.select { |job| job[:job] == TransportationModes::ReclassifyTrackJob }
      expect(jobs.map { |job| job[:args].first }).to eq(tracks.map(&:id).sort)
      expect(jobs.first[:at]).to eq(Time.current.to_f)
      expect(jobs.last[:at]).to eq(10.seconds.from_now.to_f)
    end

    status = Tracks::TransportationRecalculationStatus.new(user.id)
    expect(status.in_progress?).to be true
    expect(status.data['total_tracks']).to eq(tracks.size)
    expect(status.data['processed_tracks']).to eq(0)
    expect(described_class.get_sidekiq_options['retry']).to be false
  end

  it 'completes immediately for users without tracks' do
    described_class.perform_now(user.id)
    expect(Tracks::TransportationRecalculationStatus.new(user.id).current_status).to eq('completed')
  end

  it 'silently skips missing users' do
    expect { described_class.perform_now(-1) }.not_to raise_error
  end

  it 'marks the status failed when the fan-out raises so the UI never spins forever' do
    create(:track, user: user)
    allow(ActiveJob).to receive(:perform_all_later).and_raise(RedisClient::CannotConnectError, 'redis down')

    expect { described_class.perform_now(user.id) }.to raise_error(RedisClient::CannotConnectError)
    expect(Tracks::TransportationRecalculationStatus.new(user.id).current_status).to eq('failed')
    expect(Tracks::TransportationRecalculationStatus.new(user.id).data['processed_tracks']).to eq(0)
  end
end
