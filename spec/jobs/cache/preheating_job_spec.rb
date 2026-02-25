# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Cache::PreheatingJob do
  before { Rails.cache.clear }

  describe '#perform' do
    let!(:user1) { create(:user) }
    let!(:user2) { create(:user) }
    let!(:import1) { create(:import, user: user1) }
    let!(:import2) { create(:import, user: user2) }
    let(:user_1_years_tracked_key) { "dawarich/user_#{user1.id}_years_tracked" }
    let(:user_2_years_tracked_key) { "dawarich/user_#{user2.id}_years_tracked" }
    let(:user_1_points_geocoded_stats_key) { "dawarich/user_#{user1.id}_points_geocoded_stats" }
    let(:user_2_points_geocoded_stats_key) { "dawarich/user_#{user2.id}_points_geocoded_stats" }
    let(:user_1_countries_visited_key) { "dawarich/user_#{user1.id}_countries_visited" }
    let(:user_2_countries_visited_key) { "dawarich/user_#{user2.id}_countries_visited" }
    let(:user_1_cities_visited_key) { "dawarich/user_#{user1.id}_cities_visited" }
    let(:user_2_cities_visited_key) { "dawarich/user_#{user2.id}_cities_visited" }

    before do
      create_list(:point, 3, user: user1, import: import1, reverse_geocoded_at: Time.current)
      create_list(:point, 2, user: user2, import: import2, reverse_geocoded_at: Time.current)
    end

    it 'preheats years_tracked cache for all users' do
      # Clear cache before test to ensure clean state
      Rails.cache.clear

      described_class.new.perform

      # Verify that cache keys exist after job runs
      expect(Rails.cache.exist?(user_1_years_tracked_key)).to be true
      expect(Rails.cache.exist?(user_2_years_tracked_key)).to be true

      # Verify the cached data is reasonable
      user1_years = Rails.cache.read(user_1_years_tracked_key)
      user2_years = Rails.cache.read(user_2_years_tracked_key)

      expect(user1_years).to be_an(Array)
      expect(user2_years).to be_an(Array)
    end

    it 'preheats points_geocoded_stats cache for all users' do
      # Clear cache before test to ensure clean state
      Rails.cache.clear

      described_class.new.perform

      # Verify that cache keys exist after job runs
      expect(Rails.cache.exist?(user_1_points_geocoded_stats_key)).to be true
      expect(Rails.cache.exist?(user_2_points_geocoded_stats_key)).to be true

      # Verify the cached data has the expected structure
      user1_stats = Rails.cache.read(user_1_points_geocoded_stats_key)
      user2_stats = Rails.cache.read(user_2_points_geocoded_stats_key)

      expect(user1_stats).to be_a(Hash)
      expect(user1_stats).to have_key(:geocoded)
      expect(user1_stats).to have_key(:without_data)
      expect(user1_stats[:geocoded]).to eq(3)

      expect(user2_stats).to be_a(Hash)
      expect(user2_stats).to have_key(:geocoded)
      expect(user2_stats).to have_key(:without_data)
      expect(user2_stats[:geocoded]).to eq(2)
    end

    it 'actually writes to cache' do
      described_class.new.perform

      expect(Rails.cache.exist?(user_1_years_tracked_key)).to be true
      expect(Rails.cache.exist?(user_1_points_geocoded_stats_key)).to be true
      expect(Rails.cache.exist?(user_1_countries_visited_key)).to be true
      expect(Rails.cache.exist?(user_1_cities_visited_key)).to be true
      expect(Rails.cache.exist?(user_2_years_tracked_key)).to be true
      expect(Rails.cache.exist?(user_2_points_geocoded_stats_key)).to be true
      expect(Rails.cache.exist?(user_2_countries_visited_key)).to be true
      expect(Rails.cache.exist?(user_2_cities_visited_key)).to be true
    end

    it 'handles users with no points gracefully' do
      user_no_points = create(:user)

      expect { described_class.new.perform }.not_to raise_error

      cached_stats = Rails.cache.read("dawarich/user_#{user_no_points.id}_points_geocoded_stats")
      expect(cached_stats).to eq({ geocoded: 0, without_data: 0 })
    end
  end
end
