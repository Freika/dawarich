# frozen_string_literal: true

class AddCountryNameToPoints < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_column :points, :country_name, :string
    add_index :points, :country_name, algorithm: :concurrently

    enqueue_backfill_job
  end

  private

  # Tolerate the job class being renamed/removed in a future version, and
  # tolerate Sidekiq/Redis being unavailable during db:migrate. The schema
  # change is the contract; the backfill is opportunistic.
  def enqueue_backfill_job
    DataMigrations::BackfillCountryNameJob.perform_later
  rescue StandardError => e
    Rails.logger.warn "[Migration] Could not enqueue BackfillCountryNameJob: #{e.message}"
  end
end
