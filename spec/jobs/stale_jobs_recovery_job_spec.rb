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

      it 'persists the error and notification in the recipient saved locale' do
        user.update!(settings: { 'locale' => 'fr' })

        I18n.with_locale(:en) { described_class.new.perform }

        expect(stale_export.reload.error_message)
          .to eq("Le délai d'exportation a expiré car son traitement était bloqué")
        notification = Notification.find_by!(user:)
        expect(notification.title).to eq("L'exportation a échoué")
        expect(notification.content).to include("L'exportation \"stale.json\" était bloquée")
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

      it 'sets error_message on stale imports' do
        described_class.new.perform

        expect(stale_import.reload.error_message).to include('stuck in processing')
      end

      it 'does not affect recent imports' do
        described_class.new.perform

        expect(recent_import.reload.status).to eq('processing')
      end

      it 'creates a notification for stale imports' do
        expect { described_class.new.perform }.to change { Notification.count }.by(1)
      end

      it 'persists the error and notification in the recipient saved locale' do
        user.update!(settings: { 'locale' => 'fr' })

        I18n.with_locale(:en) { described_class.new.perform }

        expect(stale_import.reload.error_message)
          .to eq("Le délai d'importation a expiré car son traitement était bloqué")
        notification = Notification.find_by!(user:)
        expect(notification.title).to eq("L'importation a échoué")
        expect(notification.content).to include("L'importation de \"#{stale_import.name}\"")
      end
    end

    context 'with no stale jobs' do
      it 'does not create any notifications' do
        expect { described_class.new.perform }.not_to(change { Notification.count })
      end
    end

    context 'with extractions in flight' do
      let(:metrics) { Yabeda.dawarich_imports }

      def extraction(status, started_at)
        import = create(:import, user: user, source: :google_phone_takeout)
        payload = started_at ? { 'started_at' => started_at.iso8601 } : {}
        import.update_columns(
          additional_data_extraction_status: Import.additional_data_extraction_statuses[status],
          additional_data_extraction: payload
        )
        import
      end

      let!(:stalled_pending) { extraction(:pending, 7.hours.ago) }
      let!(:running_without_start) { extraction(:running, nil) }

      before do
        extraction(:pending, 10.minutes.ago)
        extraction(:running, 2.hours.ago)
        extraction(:completed, 30.hours.ago)
        allow(Rails.logger).to receive(:warn).and_call_original
      end

      it 'reports the oldest age per state and the stalled count without changing any extraction' do
        expect { described_class.new.perform }
          .not_to(change { Import.order(:id).pluck(:additional_data_extraction_status, :additional_data_extraction) })

        expect(metrics.extraction_oldest_age_seconds.get(state: 'pending')).to be_within(60).of(7.hours.to_i)
        expect(metrics.extraction_oldest_age_seconds.get(state: 'running')).to be_within(60).of(2.hours.to_i)
        expect(metrics.extractions_stalled.get).to eq(2)
      end

      it 'logs only the stalled import ids' do
        described_class.new.perform

        ids = [stalled_pending.id, running_without_start.id].sort.join(',')
        expect(Rails.logger).to have_received(:warn)
          .with("event=imports.extractions_stalled count=2 import_ids=#{ids}")
      end

      it 'still reports when the stale-export recovery fails' do
        metrics.extractions_stalled.set({}, 0)
        allow(Export).to receive(:processing).and_raise(ActiveRecord::StatementInvalid, 'boom')

        expect { described_class.new.perform }.to raise_error(ActiveRecord::StatementInvalid)

        expect(metrics.extractions_stalled.get).to eq(2)
      end

      it 'drops back to zero once nothing is in flight' do
        described_class.new.perform
        Import.update_all(additional_data_extraction_status: Import.additional_data_extraction_statuses[:completed])

        described_class.new.perform

        expect(metrics.extraction_oldest_age_seconds.get(state: 'pending')).to eq(0)
        expect(metrics.extraction_oldest_age_seconds.get(state: 'running')).to eq(0)
        expect(metrics.extractions_stalled.get).to eq(0)
      end
    end
  end
end
