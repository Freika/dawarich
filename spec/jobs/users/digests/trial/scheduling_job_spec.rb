# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::Digests::Trial::SchedulingJob, type: :job do
  describe '#perform' do
    def run_job
      described_class.perform_now
    end

    let!(:ending_tomorrow) { create(:user, :trial, skip_auto_trial: true, active_until: 1.day.from_now) }

    it 'enqueues a calculating job for a trial user whose trial ends tomorrow' do
      expect { run_job }
        .to have_enqueued_job(Users::Digests::Trial::CalculatingJob)
        .with(ending_tomorrow.id)
        .exactly(:once)
    end

    it 'runs on the digests queue' do
      expect(described_class.new.queue_name).to eq('digests')
    end

    it 'does not enqueue for a trial user five days out' do
      far_out = create(:user, :trial, skip_auto_trial: true, active_until: 5.days.from_now)

      expect { run_job }.not_to have_enqueued_job(Users::Digests::Trial::CalculatingJob).with(far_out.id)
    end

    it 'does not enqueue for a trial user whose trial already ended' do
      expired = create(:user, :trial, skip_auto_trial: true, active_until: 1.day.ago)

      expect { run_job }.not_to have_enqueued_job(Users::Digests::Trial::CalculatingJob).with(expired.id)
    end

    it 'does not enqueue for an active user ending tomorrow' do
      active = create(:user, skip_auto_trial: true, status: :active, active_until: 1.day.from_now)

      expect { run_job }.not_to have_enqueued_job(Users::Digests::Trial::CalculatingJob).with(active.id)
    end

    it 'does not enqueue for a trial user with no active_until' do
      undated = create(:user, :trial, skip_auto_trial: true, active_until: nil)

      expect { run_job }.not_to have_enqueued_job(Users::Digests::Trial::CalculatingJob).with(undated.id)
    end

    context 'when the cohort exceeds the per-run cap' do
      before do
        stub_const("#{described_class}::MAX_PER_RUN", 1)
        create(:user, :trial, skip_auto_trial: true, active_until: 1.day.from_now)
      end

      it 'truncates the cohort to the cap' do
        expect { run_job }.to have_enqueued_job(Users::Digests::Trial::CalculatingJob).exactly(:once)
      end

      it 'logs the truncation' do
        allow(Rails.logger).to receive(:warn)

        run_job

        expect(Rails.logger).to have_received(:warn).with(/exceeded/i)
      end
    end

    context 'when the cohort fits within the cap' do
      it 'does not log a truncation warning' do
        allow(Rails.logger).to receive(:warn)

        run_job

        expect(Rails.logger).not_to have_received(:warn).with(/exceeded/i)
      end
    end
  end
end
