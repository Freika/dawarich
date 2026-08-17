# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Cache::PreheatingJob do
  before { Rails.cache.clear }

  describe '#perform' do
    let!(:user1) { create(:user) }
    let!(:user2) { create(:user) }

    it 'runs on the cache queue' do
      expect(described_class.new.queue_name).to eq('cache')
    end

    it 'preheats the global country borders cache' do
      described_class.new.perform

      expect(Rails.cache.exist?('dawarich/countries_codes')).to be true
    end

    it 'fans out one job per user instead of preheating inline' do
      described_class.new.perform

      expect(Cache::UserPreheatingJob).to have_been_enqueued.with(user1.id)
      expect(Cache::UserPreheatingJob).to have_been_enqueued.with(user2.id)
    end

    it 'enqueues exactly one job per user' do
      expect { described_class.new.perform }
        .to have_enqueued_job(Cache::UserPreheatingJob).exactly(User.count).times
    end

    it 'does not write per-user caches itself' do
      described_class.new.perform

      expect(Rails.cache.exist?("dawarich/user_#{user1.id}_years_tracked")).to be false
    end

    it 'preheats every user once the fanned-out jobs run' do
      perform_enqueued_jobs { described_class.new.perform }

      expect(Rails.cache.exist?("dawarich/user_#{user1.id}_years_tracked")).to be true
      expect(Rails.cache.exist?("dawarich/user_#{user2.id}_years_tracked")).to be true
    end
  end
end
