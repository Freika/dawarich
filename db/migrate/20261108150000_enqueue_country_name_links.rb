# frozen_string_literal: true

class EnqueueCountryNameLinks < ActiveRecord::Migration[8.0]
  ENQUEUED_KEY = 'country_name_links_enqueued'

  # Same gate as the earlier country backfills: self-hosted only, honouring the
  # opt-out variable; Dawarich Cloud runs the job by hand. It only writes rows
  # whose country_id is still NULL and whose name a linked row explains.
  #
  # An empty point_sources means the dimension chain has not run yet; its
  # country backfill starts this job when it finishes. An upgrade that also
  # queues country backfills (each chains a run) links more than once, the
  # first run early: accepted, because a run only fills NULLs and the last one
  # sees all the evidence.
  def up
    return unless DataMigrations::AddPointDimensionColumnsJob.backfill_allowed?
    return unless select_value('SELECT EXISTS (SELECT 1 FROM point_sources)')

    connection.transaction do
      connection.execute('SELECT pg_advisory_xact_lock(20261108150000)')
      metadata = connection.pool.internal_metadata
      next if metadata[ENQUEUED_KEY] == 'true'

      job = DataMigrations::LinkCountryNamesJob.perform_later
      metadata[ENQUEUED_KEY] = 'true' if job&.successfully_enqueued?
    end
  rescue NameError
    raise
  rescue StandardError => e
    Rails.logger.error(
      "[EnqueueCountryNameLinks] could not enqueue the job (#{e.class}: #{e.message}). " \
      'Start it later with: DataMigrations::LinkCountryNamesJob.perform_later'
    )
  end

  def down; end
end
