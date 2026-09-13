# frozen_string_literal: true

class DataMigrations::BackfillFamilyMemberEntitlementsJob < ApplicationJob
  queue_as :data_migrations

  BATCH_SIZE = 200

  def perform
    return if DawarichSettings.self_hosted?

    Rails.logger.info('Starting family member entitlement backfill')

    total = 0

    Family.find_in_batches(batch_size: BATCH_SIZE) do |batch|
      batch.each do |family|
        Families::SyncMembers.new(family: family, notify: false).call
        total += 1
      end
    end

    Rails.logger.info("Completed family member entitlement backfill. Synced #{total} families")
  end
end
