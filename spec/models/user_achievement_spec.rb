# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UserAchievement do
  describe 'validations' do
    it 'enforces one award per user and achievement' do
      existing = create(:user_achievement)
      duplicate = build(:user_achievement, user: existing.user, achievement_key: existing.achievement_key)

      expect(duplicate).not_to be_valid
    end

    it 'requires earned_at' do
      expect(build(:user_achievement, earned_at: nil)).not_to be_valid
    end
  end
end
