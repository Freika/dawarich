# frozen_string_literal: true

namespace :achievements do
  desc 'Load region geometries (idempotent) and enqueue a staggered exploration backfill'
  task backfill: :environment do
    if Country.none?
      warn 'Skipping achievements backfill: countries table is empty (run db:seed first).'
    else
      expected_regions = Achievements::Registry.subdivision_codes.size
      loaded_regions = Region.where(code: Achievements::Registry.subdivision_codes).count
      Achievements::LoadRegions.new.call if loaded_regions < expected_regions
      # Release tasks can finish before existing Sidekiq processes have been
      # replaced. Delay dispatch so only workers running this release consume
      # the new job signature.
      Achievements::BulkCheckJob.set(wait: 2.minutes).perform_later(
        notify: false, force: true, stale_only: true
      )
    end
  end
end
