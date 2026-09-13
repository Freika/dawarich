# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Cache::PreheatingJob do
  before { Rails.cache.clear }

  describe '#perform' do
    # skip_auto_trial pins the factory status: the after_commit :activate /
    # :start_trial hooks would otherwise rewrite it based on self_hosted?,
    # which these examples stub per context.
    let!(:active_user) { create(:user, skip_auto_trial: true) }
    let!(:trial_user) { create(:user, :trial, skip_auto_trial: true) }
    let!(:inactive_user) { create(:user, :inactive, skip_auto_trial: true) }
    let!(:pending_payment_user) { create(:user, status: :pending_payment, skip_auto_trial: true) }

    it 'runs on the cache queue' do
      expect(described_class.new.queue_name).to eq('cache')
    end

    it 'preheats the global country borders cache' do
      described_class.new.perform

      expect(Rails.cache.exist?('dawarich/countries_codes')).to be true
    end

    it 'does not write per-user caches itself' do
      described_class.new.perform

      expect(Rails.cache.exist?("dawarich/user_#{active_user.id}_years_tracked")).to be false
    end

    context 'on Dawarich Cloud' do
      before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

      it 'fans out to active users' do
        described_class.new.perform

        expect(Cache::UserPreheatingJob).to have_been_enqueued.with(active_user.id)
      end

      it 'fans out to trial users' do
        described_class.new.perform

        expect(Cache::UserPreheatingJob).to have_been_enqueued.with(trial_user.id)
      end

      it 'skips inactive users' do
        described_class.new.perform

        expect(Cache::UserPreheatingJob).not_to have_been_enqueued.with(inactive_user.id)
      end

      it 'skips users pending payment' do
        described_class.new.perform

        expect(Cache::UserPreheatingJob).not_to have_been_enqueued.with(pending_payment_user.id)
      end

      it 'enqueues exactly one job per active or trial user' do
        described_class.new.perform

        preheated = enqueued_jobs.filter_map do |job|
          job[:args].first if job[:job] == Cache::UserPreheatingJob
        end

        expect(preheated.count(active_user.id)).to eq(1)
        expect(preheated.count(trial_user.id)).to eq(1)
        expect(preheated).not_to include(inactive_user.id, pending_payment_user.id)
      end

      it 'preheats the fanned-out users once their jobs run' do
        perform_enqueued_jobs { described_class.new.perform }

        expect(Rails.cache.exist?("dawarich/user_#{active_user.id}_years_tracked")).to be true
        expect(Rails.cache.exist?("dawarich/user_#{trial_user.id}_years_tracked")).to be true
        expect(Rails.cache.exist?("dawarich/user_#{inactive_user.id}_years_tracked")).to be false
      end
    end

    context 'when self-hosted' do
      before { allow(DawarichSettings).to receive(:self_hosted?).and_return(true) }

      it 'fans out to every user regardless of status' do
        described_class.new.perform

        expect(Cache::UserPreheatingJob).to have_been_enqueued.with(active_user.id)
        expect(Cache::UserPreheatingJob).to have_been_enqueued.with(trial_user.id)
        expect(Cache::UserPreheatingJob).to have_been_enqueued.with(inactive_user.id)
        expect(Cache::UserPreheatingJob).to have_been_enqueued.with(pending_payment_user.id)
      end

      it 'enqueues exactly one job per user' do
        expect { described_class.new.perform }
          .to have_enqueued_job(Cache::UserPreheatingJob).exactly(User.count).times
      end
    end
  end
end
