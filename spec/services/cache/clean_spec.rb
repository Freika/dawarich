# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Cache::Clean do
  before { Rails.cache.clear }

  describe '.call' do
    let!(:user1) { create(:user) }
    let!(:user2) { create(:user) }
    let(:user_1_years_tracked_key) { "dawarich/user_#{user1.id}_years_tracked" }
    let(:user_2_years_tracked_key) { "dawarich/user_#{user2.id}_years_tracked" }
    let(:user_1_points_geocoded_stats_key) { "dawarich/user_#{user1.id}_points_geocoded_stats" }
    let(:user_2_points_geocoded_stats_key) { "dawarich/user_#{user2.id}_points_geocoded_stats" }
    let(:user_1_countries_key) { "dawarich/user_#{user1.id}_countries" }
    let(:user_2_countries_key) { "dawarich/user_#{user2.id}_countries" }
    let(:user_1_cities_key) { "dawarich/user_#{user1.id}_cities" }
    let(:user_2_cities_key) { "dawarich/user_#{user2.id}_cities" }

    before do
      # Set up cache entries that should be cleaned
      Rails.cache.write('cache_jobs_scheduled', true)
      Rails.cache.write(CheckAppVersion::VERSION_CACHE_KEY, '1.0.0')
      Rails.cache.write(user_1_years_tracked_key, { 2023 => %w[Jan Feb] })
      Rails.cache.write(user_2_years_tracked_key, { 2023 => %w[Mar Apr] })
      Rails.cache.write(user_1_points_geocoded_stats_key, { geocoded: 5, without_data: 2 })
      Rails.cache.write(user_2_points_geocoded_stats_key, { geocoded: 3, without_data: 1 })
    end

    it 'deletes control flag cache' do
      expect(Rails.cache.exist?('cache_jobs_scheduled')).to be true

      described_class.call

      expect(Rails.cache.exist?('cache_jobs_scheduled')).to be false
    end

    it 'deletes version cache' do
      expect(Rails.cache.exist?(CheckAppVersion::VERSION_CACHE_KEY)).to be true

      described_class.call

      expect(Rails.cache.exist?(CheckAppVersion::VERSION_CACHE_KEY)).to be false
    end

    it 'deletes years tracked cache for all users' do
      expect(Rails.cache.exist?(user_1_years_tracked_key)).to be true
      expect(Rails.cache.exist?(user_2_years_tracked_key)).to be true

      described_class.call

      expect(Rails.cache.exist?(user_1_years_tracked_key)).to be false
      expect(Rails.cache.exist?(user_2_years_tracked_key)).to be false
    end

    it 'deletes points geocoded stats cache for all users' do
      expect(Rails.cache.exist?(user_1_points_geocoded_stats_key)).to be true
      expect(Rails.cache.exist?(user_2_points_geocoded_stats_key)).to be true

      described_class.call

      expect(Rails.cache.exist?(user_1_points_geocoded_stats_key)).to be false
      expect(Rails.cache.exist?(user_2_points_geocoded_stats_key)).to be false
    end

    it 'deletes countries and cities cache for all users' do
      Rails.cache.write(user_1_countries_key, %w[USA Canada])
      Rails.cache.write(user_2_countries_key, %w[France Germany])
      Rails.cache.write(user_1_cities_key, ['New York', 'Toronto'])
      Rails.cache.write(user_2_cities_key, %w[Paris Berlin])

      expect(Rails.cache.exist?(user_1_countries_key)).to be true
      expect(Rails.cache.exist?(user_2_countries_key)).to be true
      expect(Rails.cache.exist?(user_1_cities_key)).to be true
      expect(Rails.cache.exist?(user_2_cities_key)).to be true

      described_class.call

      expect(Rails.cache.exist?(user_1_countries_key)).to be false
      expect(Rails.cache.exist?(user_2_countries_key)).to be false
      expect(Rails.cache.exist?(user_1_cities_key)).to be false
      expect(Rails.cache.exist?(user_2_cities_key)).to be false
    end

    it 'logs cache cleaning process' do
      expect(Rails.logger).to receive(:info).with('Cleaning cache...')
      expect(Rails.logger).to receive(:info).with('Cache cleaned')

      described_class.call
    end

    it 'handles users being added during execution gracefully' do
      # Create a user that will be found during the cleaning process
      user3 = nil

      allow(User).to receive(:find_each).and_yield(user1).and_yield(user2) do |&block|
        # Create a new user while iterating - this should not cause errors
        user3 = create(:user)
        Rails.cache.write("dawarich/user_#{user3.id}_years_tracked", { 2023 => ['May'] })
        Rails.cache.write("dawarich/user_#{user3.id}_points_geocoded_stats", { geocoded: 1, without_data: 0 })

        # Continue with the original block
        [user1, user2].each(&block)
      end

      expect { described_class.call }.not_to raise_error

      # The new user's cache should still exist since it wasn't processed
      expect(Rails.cache.exist?("dawarich/user_#{user3.id}_years_tracked")).to be true
      expect(Rails.cache.exist?("dawarich/user_#{user3.id}_points_geocoded_stats")).to be true
    end
  end
end
