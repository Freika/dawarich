# frozen_string_literal: true

class BackfillFamilyMemberEntitlements < ActiveRecord::Migration[8.0]
  def up
    DataMigrations::BackfillFamilyMemberEntitlementsJob.perform_later
  rescue StandardError => e
    Rails.logger.warn "[Migration] Could not enqueue BackfillFamilyMemberEntitlementsJob: #{e.message}"
  end

  def down
    # no-op: backfill is non-destructive
  end
end
