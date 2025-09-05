# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Cache::PreheatingJob do
  before do
    Rails.cache.clear
  end

  describe '#perform' do
    let!(:user1) { create(:user) }
    let!(:user2) { create(:user) }
    let!(:import1) { create(:import, user: user1) }
    let!(:import2) { create(:import, user: user2) }

    before do
      create_list(:point, 3, user: user1, import: import1, reverse_geocoded_at: Time.current)
      create_list(:point, 2, user: user2, import: import2, reverse_geocoded_at: Time.current)
    end

    it 'preheats years_tracked cache for all users' do
      expect(Rails.cache).to receive(:write).with(
        "dawarich/user_#{user1.id}_years_tracked",
        anything,
        expires_in: 1.day
      )
      expect(Rails.cache).to receive(:write).with(
        "dawarich/user_#{user2.id}_years_tracked",
        anything,
        expires_in: 1.day
      )

      described_class.new.perform
    end

    it 'preheats points_geocoded_stats cache for all users' do
      expect(Rails.cache).to receive(:write).with(
        "dawarich/user_#{user1.id}_points_geocoded_stats",
        { geocoded: 3, without_data: 0 },
        expires_in: 1.day
      )
      expect(Rails.cache).to receive(:write).with(
        "dawarich/user_#{user2.id}_points_geocoded_stats",
        { geocoded: 2, without_data: 0 },
        expires_in: 1.day
      )

      described_class.new.perform
    end

    it 'actually writes to cache' do
      described_class.new.perform

      expect(Rails.cache.exist?("dawarich/user_#{user1.id}_years_tracked")).to be true
      expect(Rails.cache.exist?("dawarich/user_#{user1.id}_points_geocoded_stats")).to be true
      expect(Rails.cache.exist?("dawarich/user_#{user2.id}_years_tracked")).to be true
      expect(Rails.cache.exist?("dawarich/user_#{user2.id}_points_geocoded_stats")).to be true
    end

    it 'handles users with no points gracefully' do
      user_no_points = create(:user)
      
      expect { described_class.new.perform }.not_to raise_error
      
      cached_stats = Rails.cache.read("dawarich/user_#{user_no_points.id}_points_geocoded_stats")
      expect(cached_stats).to eq({ geocoded: 0, without_data: 0 })
    end
  end
end