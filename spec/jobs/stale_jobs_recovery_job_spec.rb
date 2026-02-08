# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StaleJobsRecoveryJob do
  describe '#perform' do
    let(:user) { create(:user) }

    context 'with stale exports' do
      let!(:stale_export) do
        export = create(:export, user: user, name: 'stale.json', status: :processing,
                        start_at: 1.week.ago, end_at: Time.current)
        export.update_column(:processing_started_at, 3.hours.ago)
        export
      end

      let!(:recent_export) do
        export = create(:export, user: user, name: 'recent.json', status: :processing,
                        start_at: 1.week.ago, end_at: Time.current)
        export.update_column(:processing_started_at, 30.minutes.ago)
        export
      end

      it 'marks stale exports as failed' do
        described_class.new.perform

        expect(stale_export.reload.status).to eq('failed')
      end

      it 'sets error_message on stale exports' do
        described_class.new.perform

        expect(stale_export.reload.error_message).to include('stuck in processing')
      end

      it 'does not affect recent exports' do
        described_class.new.perform

        expect(recent_export.reload.status).to eq('processing')
      end

      it 'creates a notification for stale exports' do
        expect { described_class.new.perform }.to change { Notification.count }.by(1)
      end
    end

    context 'with stale imports' do
      let!(:stale_import) do
        imp = create(:import, user: user, status: :processing)
        imp.update_column(:processing_started_at, 7.hours.ago)
        imp
      end

      let!(:recent_import) do
        imp = create(:import, user: user, status: :processing)
        imp.update_column(:processing_started_at, 2.hours.ago)
        imp
      end

      it 'marks stale imports as failed' do
        described_class.new.perform

        expect(stale_import.reload.status).to eq('failed')
      end

      it 'does not affect recent imports' do
        described_class.new.perform

        expect(recent_import.reload.status).to eq('processing')
      end

      it 'creates a notification for stale imports' do
        expect { described_class.new.perform }.to change { Notification.count }.by(1)
      end
    end

    context 'with no stale jobs' do
      it 'does not create any notifications' do
        expect { described_class.new.perform }.not_to(change { Notification.count })
      end
    end
  end
end
