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

    it 'handles users with zero points' do
      user.update_column(:points_count, 5)

      described_class.new.perform

      expect(user.reload.points_count).to eq(0)
    end

    it 'corrects trial users and skips pending_payment users' do
      trial = create(:user).tap { |u| u.update_column(:status, 2) }
      unpaid = create(:user).tap { |u| u.update_column(:status, 3) }
      [trial, unpaid].each do |u|
        create(:point, user: u)
        u.update_column(:points_count, 9)
      end

      described_class.new.perform

      expect([trial.reload.points_count, unpaid.reload.points_count]).to eq([1, 9])
    end

    it 'skips soft-deleted users' do
      deleted = create(:user)
      create(:point, user: deleted)
      deleted.update_columns(points_count: 9, deleted_at: 1.day.ago)

      described_class.new.perform

      expect(User.unscoped.find(deleted.id).points_count).to eq(9)
    end

    it 'does not touch updated_at when it corrects the count' do
      user.update_column(:points_count, 4)

      expect { described_class.new.perform }.not_to(change { user.reload.updated_at })
      expect(user.points_count).to eq(0)
    end

    it 'changes nothing while Oban owns the cron entry' do
      job_owner!('cron:points_counter_correction_job', :oban)
      user.update_column(:points_count, 10)

      described_class.new.perform

      expect(user.reload.points_count).to eq(10)
    end

    it 'stops at the first batch after Oban takes the cron entry' do
      stub_const("#{described_class}::BATCH_SIZE", 1)
      second = create(:user)
      third = create(:user)
      [user, second, third].each { |u| u.update_column(:points_count, 7) }
      allow(JobOwnership).to receive(:with_owner).and_wrap_original do |original, *args, &block|
        original.call(*args, &block).tap { job_owner!('cron:points_counter_correction_job', :oban) }
      end

      described_class.new.perform

      expect([user.reload.points_count, second.reload.points_count, third.reload.points_count]).to eq([0, 7, 7])
      expect(JobOwnership).to have_received(:with_owner).twice
    end
  end
end
