# frozen_string_literal: true

class BackfillFamilyMemberEntitlements < ActiveRecord::Migration[8.0]
  def up
    DataMigrations::BackfillFamilyMemberEntitlementsJob.perform_later
  rescue StandardError => e
    Rails.logger.warn "[Migration] job=BackfillFamilyMemberEntitlementsJob enqueued=false error=#{e.message}"
  end

  def down; end
end
