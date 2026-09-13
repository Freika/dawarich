# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::PrefillPointsCounterCacheJob do
  describe 'resumption' do
    let!(:users) do
      Array.new(6) do
        create(:user).tap do |user|
          create(:point, user: user)
          user.update_column(:points_count, 0)
        end
      end
    end

    def counters
      User.where(id: users.map(&:id)).order(:id).pluck(:points_count)
    end

    it 'stops partway through when the worker is shutting down' do
      described_class.perform_later(batch_size: 2)

      interrupt_job_during_step(described_class, :prefill, cursor: users[3].id) do
        perform_enqueued_jobs
      end

      expect(counters).to eq([1, 1, 1, 1, 0, 0])
    end

    it 'finishes the remaining users when it resumes' do
      described_class.perform_later(batch_size: 2)

      interrupt_job_during_step(described_class, :prefill, cursor: users[3].id) do
        perform_enqueued_jobs
      end
      perform_enqueued_jobs

      expect(counters).to all(eq(1))
    end

    it 'still prefills a single user when given an id' do
      described_class.perform_now(users.first.id)

      expect(users.first.reload.points_count).to eq(1)
    end

    it 'completes in a single run when the worker is not shutting down' do
      perform_enqueued_jobs { described_class.perform_later(batch_size: 2) }

      expect(counters).to all(eq(1))
      expect(enqueued_jobs).to be_empty
    end
  end
end
