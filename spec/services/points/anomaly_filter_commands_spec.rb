# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::AnomalyFilterCommands do
  let(:user) { create(:user) }

  it 'enqueues Rails tracks with the requested queue under their current owner' do
    track = create(:track, user:)
    payload = { 'user_id' => user.id, 'track_id' => track.id, 'job_queue' => 'low_priority' }
    expect { described_class::HANDLERS.fetch('points.anomaly_recalculate').fetch(:call).call(payload) }
      .to have_enqueued_job(Tracks::RecalculateJob).with(track.id).on_queue('low_priority')
  end

  it 'keeps the default tracks queue' do
    track = create(:track, user:)
    payload = { 'user_id' => user.id, 'track_id' => track.id, 'job_queue' => nil }
    expect { described_class::HANDLERS.fetch('points.anomaly_recalculate').fetch(:call).call(payload) }
      .to have_enqueued_job(Tracks::RecalculateJob).with(track.id).on_queue('tracks')
  end

  it 'does not recalculate another users track' do
    track = create(:track)
    payload = { 'user_id' => user.id, 'track_id' => track.id, 'job_queue' => nil }
    expect { described_class::HANDLERS.fetch('points.anomaly_recalculate').fetch(:call).call(payload) }
      .not_to have_enqueued_job(Tracks::RecalculateJob)
  end

  it 'produces the queue-aware native command when the canonical tracks lane changes owner' do
    track = create(:track, user:)
    allow(JobOwnership).to receive(:lock_owner).with('command:tracks.recalculate').and_return(:oban)
    allow(JobOutbox).to receive(:insert_all).and_return([1])
    payload = { 'user_id' => user.id, 'track_id' => track.id, 'job_queue' => 'low_priority' }
    described_class::HANDLERS.fetch('points.anomaly_recalculate').fetch(:call).call(payload)
    expect(JobOutbox).to have_received(:insert_all).with([hash_including(
      command_type: 'points.anomaly_recalculate', command_version: 1, payload:, aggregate_id: track.id
    )])
  end

  it 'enqueues stats with a captured zone and caller queue' do
    payload = { 'user_id' => user.id, 'year' => 2024, 'month' => 1,
                'job_queue' => 'low_priority', 'time_zone' => 'America/New_York' }
    expect { described_class::HANDLERS.fetch('points.anomaly_stats').fetch(:call).call(payload) }
      .to have_enqueued_job(Stats::CalculatingJob).with(user.id, 2024, 1).on_queue('low_priority')
    expect(enqueued_jobs.last.fetch('timezone')).to eq('America/New_York')
  end

  it 'missing users do not enqueue stats or tracks' do
    user.destroy!
    expect do
      described_class::HANDLERS.fetch('points.anomaly_stats').fetch(:call)
                               .call('user_id' => user.id, 'year' => 2024, 'month' => 1, 'job_queue' => nil,
                                     'time_zone' => 'UTC')
    end.not_to have_enqueued_job(Stats::CalculatingJob)
  end

  it 'rehomes real pending alias commands with their requested queue and schedule' do
    track = create(:track, user:)
    job_owner!('command:tracks.recalculate', :sidekiq)
    at = 1.hour.from_now
    row = JobOutbox.create!(event_id: SecureRandom.uuid, command_type: 'points.anomaly_recalculate',
                            command_version: 1, aggregate_id: track.id, scheduled_at: at,
                            payload: { 'track_id' => track.id, 'user_id' => user.id, 'job_queue' => 'low_priority' })
    expect do
      expect(described_class.rehome_pending!(by: 'spec')).to eq(moved: 1, left: 0)
    end.to have_enqueued_job(Tracks::RecalculateJob).with(track.id).on_queue('low_priority').at(at)
    expect(JobOutbox.exists?(event_id: row.event_id)).to be(false)
  end

  it 'does not rehome aliases while Oban still owns the canonical tracks lane' do
    track = create(:track, user:)
    job_owner!('command:tracks.recalculate', :oban)
    JobOutbox.create!(event_id: SecureRandom.uuid, command_type: 'points.anomaly_recalculate', command_version: 1,
                      aggregate_id: track.id, scheduled_at: Time.current,
                      payload: { 'track_id' => track.id, 'user_id' => user.id, 'job_queue' => nil })
    expect do
      expect(described_class.rehome_pending!(by: 'spec')).to eq(moved: 0, left: 1, error: 'not_owner')
    end.not_to have_enqueued_job(Tracks::RecalculateJob)
    expect(JobOutbox.count).to eq(1)
  end

  it 'leaves an alias durable when enqueue fails' do
    track = create(:track, user:)
    job_owner!('command:tracks.recalculate', :sidekiq)
    JobOutbox.create!(event_id: SecureRandom.uuid, command_type: 'points.anomaly_recalculate', command_version: 1,
                      aggregate_id: track.id, scheduled_at: Time.current,
                      payload: { 'track_id' => track.id, 'user_id' => user.id, 'job_queue' => nil })
    allow_any_instance_of(Tracks::RecalculateJob).to receive(:enqueue).and_raise(StandardError, 'adapter failed')
    expect(described_class.rehome_pending!(by: 'spec')).to eq(moved: 0, left: 1, error: 'StandardError')
    expect(JobOutbox.count).to eq(1)
  end

  it 'canonical track handback includes the alias queue before native shutdown' do
    track = create(:track, user:)
    job_owner!('command:tracks.recalculate', :oban)
    JobOutbox.create!(event_id: SecureRandom.uuid, command_type: 'points.anomaly_recalculate', command_version: 1,
                      aggregate_id: track.id, scheduled_at: Time.current,
                      payload: { 'track_id' => track.id, 'user_id' => user.id, 'job_queue' => 'low_priority' })
    expect do
      expect(JobCommands.rehome!('tracks.recalculate', by: 'spec')).to eq(moved: 1, left: 0)
    end.to have_enqueued_job(Tracks::RecalculateJob).with(track.id).on_queue('low_priority')
    expect(JobOutbox.count).to eq(0)
  end
end
