# frozen_string_literal: true

namespace :achievements do
  desc 'Load region geometries (idempotent) and enqueue a staggered exploration backfill'
  task backfill: :environment do
    if Country.none?
      warn 'Skipping achievements backfill: countries table is empty (run db:seed first).'
    else
      Achievements::LoadRegions.new.call
      Achievements::BulkCheckJob.perform_later(notify: false, force: true)
    end
  end
end
