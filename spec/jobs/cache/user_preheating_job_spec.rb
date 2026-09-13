# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Cache::UserPreheatingJob do
  before { Rails.cache.clear }

  describe '#perform' do
    let!(:user) { create(:user) }
    let!(:import) { create(:import, user: user) }

    before do
      create_list(:point, 3, user: user, import: import, reverse_geocoded_at: Time.current)
    end

    it 'runs on the cache queue' do
      expect(described_class.new.queue_name).to eq('cache')
    end

    it 'preheats years_tracked' do
      described_class.new.perform(user.id)

      expect(Rails.cache.read("dawarich/user_#{user.id}_years_tracked")).to be_an(Array)
    end

    it 'preheats points_geocoded_stats' do
      described_class.new.perform(user.id)

      stats = Rails.cache.read("dawarich/user_#{user.id}_points_geocoded_stats")

      expect(stats).to include(geocoded: 3)
      expect(stats).to have_key(:without_data)
    end

    it 'preheats countries and cities visited' do
      described_class.new.perform(user.id)

      expect(Rails.cache.exist?("dawarich/user_#{user.id}_countries_visited")).to be true
      expect(Rails.cache.exist?("dawarich/user_#{user.id}_cities_visited")).to be true
    end

    it 'preheats total_distance' do
      described_class.new.perform(user.id)

      expect(Rails.cache.exist?("dawarich/user_#{user.id}_total_distance")).to be true
    end

    it 'handles a user with no points gracefully' do
      user_without_points = create(:user)

      expect { described_class.new.perform(user_without_points.id) }.not_to raise_error

      expect(Rails.cache.read("dawarich/user_#{user_without_points.id}_points_geocoded_stats"))
        .to eq({ geocoded: 0, without_data: 0 })
    end

    context 'when the user no longer exists' do
      it 'does not raise' do
        deleted_id = create(:user).id
        User.find(deleted_id).destroy

        expect { described_class.new.perform(deleted_id) }.not_to raise_error
      end
    end
  end
end
