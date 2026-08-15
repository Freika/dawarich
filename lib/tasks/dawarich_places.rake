# frozen_string_literal: true

namespace :dawarich do
  desc 'One-time orphan suggested-place cleanup for all users'
  task cleanup_suggested_places: :environment do
    enqueued = 0
    User.in_batches(of: 100).each_with_index do |batch, i|
      batch.pluck(:id).each_with_index do |uid, j|
        Places::OrphanCleanupJob.set(wait: ((i * 100 + j) * 0.1).seconds).perform_later(uid)
        enqueued += 1
      end
    end
    # Ownerless (user_id IS NULL) orphan suggested places aren't reached by the
    # per-user passes above, so drain them in a dedicated pass after the rest.
    Places::OrphanCleanupJob.set(wait: (enqueued * 0.1).seconds).perform_later(nil)
    Rails.logger.info('[dawarich:cleanup_suggested_places] enqueued')
    Rails.logger.info(<<~MSG)
      [dawarich:cleanup_suggested_places] To verify the drain is complete, run:
        bin/rails runner 'puts Place.where(source: :photon, note: [nil, ""]).where.missing(:visits, :taggings).count'
      A return value of 0 means all orphan suggested places have been deleted and it is safe to schedule the place_visits drop.
    MSG
  end

  desc 'One-time backfill of legacy Place::DEFAULT_NAME rows'
  task backfill_place_names: :environment do
    Places::BulkNameFetchingJob.perform_later
    Rails.logger.info('[dawarich:backfill_place_names] enqueued')
  end
end
