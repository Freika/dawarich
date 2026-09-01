# frozen_string_literal: true

# Timing harness for the Release-D rewrite: seeds N synthetic v1-era rows
# into the CURRENT points table shape is not possible post-swap, so this
# benchmarks the transform SQL against a scratch copy. Run BEFORE upgrading
# (on a v1 schema) for the honest number, or accept the post-swap no-op.
#
#   bundle exec rake points_v2:benchmark ROWS=100000
namespace :points_v2 do
  desc 'Measure rewrite throughput (rows/sec) for release-notes duration math'
  task benchmark: :environment do
    connection = ActiveRecord::Base.connection

    unless connection.column_exists?(:points, :country_name)
      puts 'points is already v2-shaped - the rewrite would no-op here. ' \
           'Run this on a v1 instance (or a prod-restored copy) for real numbers.'
      next
    end

    rows = ENV.fetch('ROWS', '100000').to_i
    user = User.first || abort('needs at least one user')

    puts "seeding #{rows} synthetic points..."
    rows.clamp(1, 10_000_000).times.each_slice(10_000) do |slice|
      values = slice.map do |i|
        ts = 1_600_000_000 + i
        "(#{ts}, #{user.id}, 'bench-tracker', '12.5', 'POINT(#{12.0 + (i % 1000) * 0.0001} 51.3)', NOW(), NOW())"
      end
      connection.execute(<<~SQL)
        INSERT INTO points ("timestamp", user_id, tracker_id, velocity, lonlat, created_at, updated_at)
        VALUES #{values.join(',')}
        ON CONFLICT DO NOTHING
      SQL
    end

    require Rails.root.join('db/migrate/20260901100000_create_points_v2.rb')
    CreatePointsV2.new.up

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    DataMigrations::RewritePointsV2Job.new.run_phases_through_copy
    DataMigrations::RewritePointsV2Job.new.finish
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    copied = connection.select_value('SELECT COUNT(*) FROM points_v2').to_i
    rate = (copied / elapsed).round
    minutes_per_million = 1_000_000.0 / rate / 60
    puts "copied #{copied} rows in #{elapsed.round(1)}s — #{rate} rows/sec " \
         "(~#{minutes_per_million.round(1)} min per 1M points)"
  end
end
