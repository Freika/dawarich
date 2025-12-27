# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Cache::InvalidateUserCaches do
  let(:user) { create(:user) }
  let(:service) { described_class.new(user.id) }

  describe '#call' do
    it 'invalidates all user-related caches' do
      # Pre-populate the caches
      Rails.cache.write("dawarich/user_#{user.id}_countries_visited", ['USA', 'Canada'])
      Rails.cache.write("dawarich/user_#{user.id}_cities_visited", ['New York', 'Toronto'])
      Rails.cache.write("dawarich/user_#{user.id}_points_geocoded_stats", { geocoded: 100, without_data: 10 })

      # Verify caches are populated
      expect(Rails.cache.read("dawarich/user_#{user.id}_countries_visited")).to eq(['USA', 'Canada'])
      expect(Rails.cache.read("dawarich/user_#{user.id}_cities_visited")).to eq(['New York', 'Toronto'])
      expect(Rails.cache.read("dawarich/user_#{user.id}_points_geocoded_stats")).to eq({ geocoded: 100, without_data: 10 })

      # Invalidate caches
      service.call

      # Verify caches are cleared
      expect(Rails.cache.read("dawarich/user_#{user.id}_countries_visited")).to be_nil
      expect(Rails.cache.read("dawarich/user_#{user.id}_cities_visited")).to be_nil
      expect(Rails.cache.read("dawarich/user_#{user.id}_points_geocoded_stats")).to be_nil
    end
  end

  describe '#invalidate_countries_visited' do
    it 'deletes the countries_visited cache' do
      Rails.cache.write("dawarich/user_#{user.id}_countries_visited", ['USA', 'Canada'])

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
end
