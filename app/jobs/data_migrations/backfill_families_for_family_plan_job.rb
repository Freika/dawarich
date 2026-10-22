# frozen_string_literal: true

class DataMigrations::BackfillFamiliesForFamilyPlanJob < ApplicationJob
  queue_as :data_migrations

  BATCH_SIZE = 500

  def perform
    return if DawarichSettings.self_hosted?

    Rails.logger.info('Starting family backfill for family-plan users')

    total = 0

    users_without_family.find_in_batches(batch_size: BATCH_SIZE) do |batch|
      ActiveJob.perform_all_later(batch.map { |user| Families::AutoCreationJob.new(user.id) })
      total += batch.size
    end

    Rails.logger.info("Completed family backfill. Enqueued #{total} users")
  end

  private

  def users_without_family
    User.where(plan: :family)
        .where.missing(:family_membership)
        .where.missing(:created_family)
  end
end
