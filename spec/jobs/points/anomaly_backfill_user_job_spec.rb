# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::AnomalyBackfillUserJob, type: :job do
  let(:user) { create(:user) }

  describe '#perform with reset: true' do
    let!(:legitimate_anomaly) do
      create(:point, user: user, accuracy: 50_000, anomaly: true,
             timestamp: 30.minutes.ago.to_i,
             latitude: 52.52, longitude: 13.405,
             lonlat: 'POINT(13.405 52.52)')
    end
    let!(:wrongly_flagged) do
      create(:point, user: user, accuracy: 60, anomaly: true,
             timestamp: 29.minutes.ago.to_i,
             latitude: 52.5201, longitude: 13.4051,
             lonlat: 'POINT(13.4051 52.5201)')
    end

    it 'clears existing anomaly flags and re-evaluates with current settings' do
      described_class.new.perform(user.id, reset: true)

      expect(wrongly_flagged.reload.anomaly).not_to be true
      expect(legitimate_anomaly.reload.anomaly).to be true
    end

    it 'enqueues a tracks/stats/digests recalculation afterwards' do
      expect do
        described_class.new.perform(user.id, reset: true)
      end.to have_enqueued_job(Users::RecalculateDataJob).with(user.id, notify: true)
    end

    it 'notifies the user by default' do
      described_class.new.perform(user.id, reset: true)

      perform_enqueued_jobs(only: Users::RecalculateDataJob)

      expect(user.notifications.where(title: 'Data recalculation completed')).to exist
    end

    it 'reports that it did the work, so callers can tell a skipped run apart' do
      expect(described_class.new.perform(user.id, reset: true)).to be true
    end

    it 'invalidates the tile epoch on clear, even when re-evaluation marks nothing' do
      # Clearing un-hides points in tiles; AnomalyFilter's own bump only fires
      # when it MARKS anomalies, so the all-clear outcome relies on this path.
      allow_any_instance_of(Points::AnomalyFilter).to receive(:call).and_return(0)
      before_component = Points::TileEpoch.etag_component(user.id, 0, Time.utc(2100, 1, 1).to_i)

      described_class.new.perform(user.id, reset: true)

      expect(Points::TileEpoch.etag_component(user.id, 0, Time.utc(2100, 1, 1).to_i))
        .not_to eq(before_component)
    end

    it 'runs the recalculation inline when asked to, keeping it on the caller queue' do
      described_class.new.perform(user.id, reset: true, rebuild: :inline)

      expect(Users::RecalculateDataJob).not_to have_been_enqueued
      expect(user.notifications.where(title: 'Data recalculation completed')).to exist
    end

    it 'routes the inline track rebuild off :tracks so live tracking stays ahead' do
      described_class.new.perform(user.id, reset: true, rebuild: :inline)

      chunk_jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.select do |job|
        job[:job] == Tracks::TimeChunkProcessorJob
      end

      expect(chunk_jobs).not_to be_empty
      expect(chunk_jobs.map { |job| job[:queue] }.uniq).to eq(['low_priority'])
    end

    it 'surfaces a track lock timeout instead of letting retry_on swallow it' do
      allow(Tracks::PerUserLock).to receive(:with_user_lock).and_raise(Tracks::PerUserLock::AcquisitionTimeout)

      expect do
        described_class.new.perform(user.id, reset: true, rebuild: :inline)
      end.to raise_error(Tracks::PerUserLock::AcquisitionTimeout)

      expect(Users::RecalculateDataJob).not_to have_been_enqueued
    end

    it 'recalculates without notifying when notify is false' do
      described_class.new.perform(user.id, reset: true, notify: false)

      perform_enqueued_jobs(only: Users::RecalculateDataJob)

      expect(user.notifications.where(title: 'Data recalculation completed')).not_to exist
    end
  end

  describe '#perform without reset' do
    let!(:already_flagged) do
      create(:point, user: user, accuracy: 60, anomaly: true,
             timestamp: 30.minutes.ago.to_i)
    end

    it 'does not clear existing flags' do
      described_class.new.perform(user.id)
      expect(already_flagged.reload.anomaly).to be true
    end

    it 'does not enqueue a recalculation' do
      expect do
        described_class.new.perform(user.id)
      end.not_to have_enqueued_job(Users::RecalculateDataJob)
    end

    it 'rebuilds affected tracks itself, since no wholesale rebuild follows' do
      point = create(:point, user: user, accuracy: 6, timestamp: 30.minutes.ago.to_i,
                     latitude: 51.3402, longitude: 12.3712, lonlat: 'POINT(12.3712 51.3402)',
                     motion_data: { 'action' => 'visit',
                                    'departure_date' => '2026-05-19T18:34:25Z' })
      track = create(:track, user: user)
      point.update_column(:track_id, track.id)

      expect do
        described_class.new.perform(user.id)
      end.to have_enqueued_job(Tracks::RecalculateJob).with(track.id)
    end

    it 'routes its own rebuilds off :tracks so live tracking stays ahead' do
      point = create(:point, user: user, accuracy: 6, timestamp: 30.minutes.ago.to_i,
                     latitude: 51.3402, longitude: 12.3712, lonlat: 'POINT(12.3712 51.3402)',
                     motion_data: { 'action' => 'visit',
                                    'departure_date' => '2026-05-19T18:34:25Z' })
      track = create(:track, user: user)
      point.update_column(:track_id, track.id)

      expect do
        described_class.new.perform(user.id)
      end.to have_enqueued_job(Tracks::RecalculateJob).on_queue('low_priority')
    end
  end

  describe '#perform skips empty chunks for sparse data' do
    let(:sparse_user) { create(:user) }

    before do
      [22.months.ago, 12.months.ago, 1.month.ago].each do |bucket_anchor|
        2.times do |i|
          create(:point, user: sparse_user, accuracy: 60, anomaly: false,
                         timestamp: (bucket_anchor + i.minutes).to_i,
                         latitude: 52.52, longitude: 13.405,
                         lonlat: 'POINT(13.405 52.52)')
        end
      end
    end

    it 'invokes the AnomalyFilter once per populated month, not per 30-day chunk in the span' do
      filter_calls = 0
      allow(Points::AnomalyFilter).to receive(:new).and_wrap_original do |original, *args, **kwargs|
        filter_calls += 1
        original.call(*args, **kwargs)
      end

      described_class.new.perform(sparse_user.id)

      expect(filter_calls).to eq(3)
    end
  end
end
