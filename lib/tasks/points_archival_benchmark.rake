# frozen_string_literal: true

require 'benchmark'

namespace :points_archival do
  desc 'Benchmark archive+restore for a user (USER_ID=). Reports wall-clock for each leg.'
  task benchmark: :environment do
    user_id = ENV.fetch('USER_ID').to_i
    count = Point.where(user_id:).count
    Rails.logger.info("Benchmarking archive+restore for user #{user_id} (#{count} points)")

    archive_t = Benchmark.realtime { Points::Archival::Archiver.new.archive_user(user_id) }
    Point.where(user_id:).in_batches(of: 10_000).delete_all
    restore_t = Benchmark.realtime { Points::Archival::Restorer.new.restore_user(user_id) }

    msg = format('archive: %<archive>.1fs  restore: %<restore>.1fs  (%<count>d points)',
                 archive: archive_t, restore: restore_t, count:)
    Rails.logger.info(msg)
    puts msg
  end
end
