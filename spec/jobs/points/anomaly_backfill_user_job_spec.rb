# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::AnomalyBackfillUserJob, type: :job do
  let(:user) { create(:user) }

  describe '#perform with reset: true' do
    let!(:legitimate_anomaly) do
      create(:point, user: user, accuracy: 5000, anomaly: true,
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

    before { user.update!(settings: { 'gps_accuracy_threshold' => 200 }) }

    it 'clears existing anomaly flags and re-evaluates with current settings' do
      described_class.new.perform(user.id, reset: true)

      expect(wrongly_flagged.reload.anomaly).not_to be true
      expect(legitimate_anomaly.reload.anomaly).to be true
    end

    it 'enqueues a tracks/stats/digests recalculation afterwards' do
      expect do
        described_class.new.perform(user.id, reset: true)
      end.to have_enqueued_job(Users::RecalculateDataJob).with(user.id)
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
  end

  describe '#perform skips empty chunks for sparse data' do
    let(:sparse_user) { create(:user) }

    before do
      sparse_user.update!(settings: { 'gps_accuracy_threshold' => 200 })

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
      allow(Points::AnomalyFilter).to receive(:new).and_wrap_original do |original, *args|
        filter_calls += 1
        original.call(*args)
      end

      described_class.new.perform(sparse_user.id)

      expect(filter_calls).to eq(3)
    end
  end
end
