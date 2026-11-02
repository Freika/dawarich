# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Cache::InvalidateUserCaches do
  let(:user) { create(:user) }
  let(:service) { described_class.new(user.id) }

  describe '#call' do
    it 'invalidates all user-related caches' do
      Rails.cache.write("dawarich/user_#{user.id}_countries_visited", %w[USA Canada])
      Rails.cache.write("dawarich/user_#{user.id}_cities_visited", ['New York', 'Toronto'])
      Rails.cache.write("dawarich/user_#{user.id}_points_geocoded_stats", { geocoded: 100, without_data: 10 })

      expect(Rails.cache.read("dawarich/user_#{user.id}_countries_visited")).to eq(%w[USA Canada])
      expect(Rails.cache.read("dawarich/user_#{user.id}_cities_visited")).to eq(['New York', 'Toronto'])
      expect(Rails.cache.read("dawarich/user_#{user.id}_points_geocoded_stats")).to eq({ geocoded: 100,
without_data: 10 })

      service.call

      expect(Rails.cache.read("dawarich/user_#{user.id}_countries_visited")).to be_nil
      expect(Rails.cache.read("dawarich/user_#{user.id}_cities_visited")).to be_nil
      expect(Rails.cache.read("dawarich/user_#{user.id}_points_geocoded_stats")).to be_nil
    end
  end

  describe '#invalidate_countries_visited' do
    it 'deletes the countries_visited cache' do
      Rails.cache.write("dawarich/user_#{user.id}_countries_visited", %w[USA Canada])

      service.invalidate_countries_visited

      expect(Rails.cache.read("dawarich/user_#{user.id}_countries_visited")).to be_nil
    end
  end

  describe '#invalidate_cities_visited' do
    it 'deletes the cities_visited cache' do
      Rails.cache.write("dawarich/user_#{user.id}_cities_visited", ['New York', 'Toronto'])

      service.invalidate_cities_visited

      expect(Rails.cache.read("dawarich/user_#{user.id}_cities_visited")).to be_nil
    end
  end

  describe '#invalidate_points_geocoded_stats' do
    it 'deletes the points_geocoded_stats cache' do
      Rails.cache.write("dawarich/user_#{user.id}_points_geocoded_stats", { geocoded: 100, without_data: 10 })

      service.invalidate_points_geocoded_stats

      expect(Rails.cache.read("dawarich/user_#{user.id}_points_geocoded_stats")).to be_nil
    end
  end

  describe '#invalidate_insights_digest' do
    let!(:digest) { create(:users_digest, user: user, year: 2024) }
    let!(:other_year) { create(:users_digest, user: user, year: 2023) }

    before do
      Rails.cache.write(digest.insights_cache_key, digest)
      Rails.cache.write(other_year.insights_cache_key, other_year)
    end

    it "deletes the year's cached digest without scanning the cache" do
      allow(Rails.cache).to receive(:delete_matched)

      described_class.new(user.id, year: 2024).invalidate_insights_digest

      expect(Rails.cache.read(digest.insights_cache_key)).to be_nil
      expect(Rails.cache.read(other_year.insights_cache_key)).to be_present
      expect(Rails.cache).not_to have_received(:delete_matched)
    end

    it 'deletes every cached yearly digest when no year is given' do
      service.invalidate_insights_digest

      expect(Rails.cache.read(digest.insights_cache_key)).to be_nil
      expect(Rails.cache.read(other_year.insights_cache_key)).to be_nil
    end
  end
end
