# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::ResetPointsCounterJob do
  describe '#perform' do
    let!(:user) { create(:user) }

    it 'corrects points_count to match actual point count' do
      create_list(:point, 3, user: user)
      user.update_column(:points_count, 10)

      described_class.new.perform(user.id)

      expect(user.reload.points_count).to eq(3)
    end

    it 'sets points_count to zero when user has no points' do
      user.update_column(:points_count, 5)

      described_class.new.perform(user.id)

      expect(user.reload.points_count).to eq(0)
    end
  end
end
