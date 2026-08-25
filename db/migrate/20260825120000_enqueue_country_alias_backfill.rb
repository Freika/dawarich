# frozen_string_literal: true

class EnqueueCountryAliasBackfill < ActiveRecord::Migration[8.0]
  # Re-runs the country resolution for instances whose first pass finished
  # before the geocoder-name aliases existed: "United States" never matched
  # the seeded "United States of America", leaving those rows unresolved.
  # The walk only touches rows whose country_id is still NULL, so it is a
  # cheap re-run everywhere the aliases have nothing to add.
  def up
    # Same gate as the dimension chain: self-hosted only, honouring the
    # opt-out variable; Dawarich Cloud runs the job by hand.
    return unless DataMigrations::AddPointDimensionColumnsJob.backfill_allowed?

    # An empty point_sources means the dimension chain has not run here yet —
    # its own tail enqueues the country job with the aliases already in
    # place, and starting a second walker now would only contend with it.
    return unless dimension_backfill_started?

    enqueue(DataMigrations::BackfillPointCountryIdJob)
  end

  def down; end

  private

  def dimension_backfill_started?
    select_value('SELECT EXISTS (SELECT 1 FROM point_sources)')
  end

  # Nothing retries this: the migration is recorded as applied either way, so
  # the log has to carry the manual remedy. A NameError still aborts — that is
  # a broken deploy, not an infrastructure hiccup.
  def enqueue(job_class)
    job_class.perform_later
  rescue NameError
    raise
  rescue StandardError => e
    Rails.logger.error(
      "[EnqueueCountryAliasBackfill] could not enqueue #{job_class} (#{e.class}: #{e.message}). " \
      "Start it later with: #{job_class}.perform_later"
    )
  end
end
