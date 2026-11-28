# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Achievements::Progress do
  describe 'validations' do
    it 'enforces one row per user and achievement' do
      existing = create(:achievement_progress)
      duplicate = build(:achievement_progress, user: existing.user, achievement_key: existing.achievement_key)

      expect(duplicate).not_to be_valid
    end

    it 'defaults state to an empty hash' do
      expect(create(:achievement_progress).state).to eq({})
    end
  end
end
