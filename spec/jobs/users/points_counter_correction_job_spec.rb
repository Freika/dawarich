# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::PointsCounterCorrectionJob do
  describe '#perform' do
    let!(:user) { create(:user) }

    it 'corrects points_count when it drifts from actual count' do
      create_list(:point, 3, user: user)
      user.update_column(:points_count, 10)

      described_class.new.perform

      expect(user.reload.points_count).to eq(3)
    end

    it 'leaves points_count unchanged when it already matches' do
      create_list(:point, 2, user: user)
      user.update_column(:points_count, 2)

      expect { described_class.new.perform }.not_to(change { user.reload.updated_at })

      expect(user.reload.points_count).to eq(2)
    end

    it 'skips inactive users' do
      inactive_user = create(:user)
      inactive_user.update_column(:status, 0) # inactive, bypass activate callback
      create_list(:point, 3, user: inactive_user)
      inactive_user.update_column(:points_count, 10)

      described_class.new.perform

      expect(inactive_user.reload.points_count).to eq(10)
    end

    it 'does not touch archived users' do
      archived = create(:user, status: :active, points_archive_state: :archived, points_count: 999)
      described_class.new.perform
      expect(archived.reload.points_count).to eq(999)
    end

    it 'handles users with zero points' do
      user.update_column(:points_count, 5)

      described_class.new.perform

      expect(user.reload.points_count).to eq(0)
    end
  end
end
