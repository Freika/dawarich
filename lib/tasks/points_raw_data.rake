# frozen_string_literal: true

namespace :points do
  namespace :raw_data do
    desc 'Restore raw_data from archive to database for a specific month'
    task :restore, %i[user_id year month] => :environment do |_t, args|
      validate_args!(args)

      user_id = args[:user_id].to_i
      year = args[:year].to_i
      month = args[:month].to_i

      puts '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
      puts '  Restoring raw_data to DATABASE'
      puts "  User: #{user_id} | Month: #{year}-#{format('%02d', month)}"
      puts '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
      puts ''

      restorer = Points::RawData::Restorer.new
      restorer.restore_to_database(user_id, year, month)

      puts ''
      puts '✓ Restoration complete!'
      puts ''
      puts "Points in #{year}-#{month} now have raw_data in database."
      puts 'Run VACUUM ANALYZE points; to update statistics.'
    end

    desc 'Restore raw_data to memory/cache temporarily (for data migrations)'
    task :restore_temporary, %i[user_id year month] => :environment do |_t, args|
      validate_args!(args)

      user_id = args[:user_id].to_i
      year = args[:year].to_i
      month = args[:month].to_i

      puts '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
      puts '  Loading raw_data into CACHE (temporary)'
      puts "  User: #{user_id} | Month: #{year}-#{format('%02d', month)}"
      puts '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
      puts ''
      puts 'Data will be available for 1 hour via Point.raw_data_with_archive accessor'
      puts ''

      restorer = Points::RawData::Restorer.new
      restorer.restore_to_memory(user_id, year, month)

      puts ''
      puts '✓ Cache loaded successfully!'
      puts ''
      puts 'You can now run your data migration.'
      puts 'Example:'
      puts "  rails runner \"Point.where(user_id: #{user_id}, timestamp_year: #{year}, timestamp_month: #{month}).find_each { |p| p.fix_coordinates_from_raw_data }\""
      puts ''
      puts 'Cache will expire in 1 hour automatically.'
    end

    desc 'Restore all archived raw_data for a user'
    task :restore_all, [:user_id] => :environment do |_t, args|
      raise 'Usage: rake points:raw_data:restore_all[user_id]' unless args[:user_id]

      user_id = args[:user_id].to_i
      user = User.find(user_id)

      puts '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
      puts '  Restoring ALL archives for user'
      puts "  #{user.email} (ID: #{user_id})"
      puts '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
      puts ''

      archives = Points::RawDataArchive.where(user_id: user_id)
                                       .select(:year, :month)
                                       .distinct
                                       .order(:year, :month)

      puts "Found #{archives.count} months to restore"
      puts ''

      archives.each_with_index do |archive, idx|
        puts "[#{idx + 1}/#{archives.count}] Restoring #{archive.year}-#{format('%02d', archive.month)}..."

        restorer = Points::RawData::Restorer.new
        restorer.restore_to_database(user_id, archive.year, archive.month)
      end

      puts ''
      puts "✓ All archives restored for user #{user_id}!"
    end

    desc 'Show archive statistics'
    task status: :environment do
      puts '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
      puts '  Points raw_data Archive Statistics'
      puts '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
      puts ''

      total_archives = Points::RawDataArchive.count
      verified_archives = Points::RawDataArchive.where.not(verified_at: nil).count
      unverified_archives = total_archives - verified_archives

      total_points = Point.count
      archived_points = Point.where(raw_data_archived: true).count
      cleared_points = Point.where(raw_data_archived: true, raw_data: {}).count
      archived_not_cleared = archived_points - cleared_points

      percentage = total_points.positive? ? (archived_points.to_f / total_points * 100).round(2) : 0

      puts "Archives: #{total_archives} (#{verified_archives} verified, #{unverified_archives} unverified)"
      puts "Points archived: #{archived_points} / #{total_points} (#{percentage}%)"
      puts "Points cleared: #{cleared_points}"
      puts "Archived but not cleared: #{archived_not_cleared}"
      puts ''

      # Storage size via ActiveStorage
      total_blob_size = ActiveStorage::Blob
                        .joins('INNER JOIN active_storage_attachments ON active_storage_attachments.blob_id = active_storage_blobs.id')
                        .where("active_storage_attachments.record_type = 'Points::RawDataArchive'")
                        .sum(:byte_size)

      puts "Storage used: #{ActiveSupport::NumberHelper.number_to_human_size(total_blob_size)}"
      puts ''

      # Recent activity
      recent = Points::RawDataArchive.where('archived_at > ?', 7.days.ago).count
      puts "Archives created last 7 days: #{recent}"
      puts ''

      # Top users
      puts 'Top 10 users by archive count:'
      puts '─────────────────────────────────────────────────'

      Points::RawDataArchive.group(:user_id)
                            .select('user_id, COUNT(*) as archive_count, SUM(point_count) as total_points')
                            .order('archive_count DESC')
                            .limit(10)
                            .each_with_index do |stat, idx|
        user = User.find(stat.user_id)
        puts "#{idx + 1}. #{user.email.ljust(30)} #{stat.archive_count.to_s.rjust(3)} archives, #{stat.total_points.to_s.rjust(8)} points"
      end

      puts ''
    end

    desc 'Verify archive integrity (all unverified archives, or specific month with args)'
    task :verify, %i[user_id year month] => :environment do |_t, args|
      verifier = Points::RawData::Verifier.new

      if args[:user_id] && args[:year] && args[:month]
        # Verify specific month
        user_id = args[:user_id].to_i
        year = args[:year].to_i
        month = args[:month].to_i

        puts '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
        puts '  Verifying Archives'
        puts "  User: #{user_id} | Month: #{year}-#{format('%02d', month)}"
        puts '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
        puts ''

        verifier.verify_month(user_id, year, month)
      else
        # Verify all unverified archives
        puts '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
        puts '  Verifying All Unverified Archives'
        puts '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
        puts ''

        stats = verifier.call

        puts ''
        puts "Verified: #{stats[:verified]}"
        puts "Failed: #{stats[:failed]}"
      end

      puts ''
      puts '✓ Verification complete!'
    end

    desc 'Clear raw_data for verified archives (all verified, or specific month with args)'
    task :clear_verified, %i[user_id year month] => :environment do |_t, args|
      clearer = Points::RawData::Clearer.new

      if args[:user_id] && args[:year] && args[:month]
        # Clear specific month
        user_id = args[:user_id].to_i
        year = args[:year].to_i
        month = args[:month].to_i

        puts '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
        puts '  Clearing Verified Archives'
        puts "  User: #{user_id} | Month: #{year}-#{format('%02d', month)}"
        puts '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
        puts ''

        clearer.clear_month(user_id, year, month)
      else
        # Clear all verified archives
        puts '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
        puts '  Clearing All Verified Archives'
        puts '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
        puts ''

        stats = clearer.call

        puts ''
        puts "Points cleared: #{stats[:cleared]}"
      end

      puts ''
      puts '✓ Clearing complete!'
      puts ''
      puts 'Run VACUUM ANALYZE points; to reclaim space and update statistics.'
    end

    desc 'Archive raw_data for old data (2+ months old, does NOT clear yet)'
    task archive: :environment do
      puts '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
      puts '  Archiving Raw Data (2+ months old data)'
      puts '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
      puts ''
      puts 'This will archive points.raw_data for months 2+ months old.'
      puts 'Raw data will NOT be cleared yet - use verify and clear_verified tasks.'
      puts 'This is safe to run multiple times (idempotent).'
      puts ''

      stats = Points::RawData::Archiver.new.call

      puts ''
      puts '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
      puts '  Archival Complete'
      puts '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
      puts ''
      puts "Months processed: #{stats[:processed]}"
      puts "Points archived: #{stats[:archived]}"
      puts "Failures: #{stats[:failed]}"
      puts ''

      return unless stats[:archived].positive?

      puts 'Next steps:'
      puts '1. Verify archives: rake points:raw_data:verify'
      puts '2. Clear verified data: rake points:raw_data:clear_verified'
      puts '3. Check stats: rake points:raw_data:status'
    end

    desc 'Full workflow: archive + verify + clear (for automated use)'
    task archive_full: :environment do
      puts '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
      puts '  Full Archive Workflow'
      puts '  (Archive → Verify → Clear)'
      puts '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
      puts ''

      # Step 1: Archive
      puts '▸ Step 1/3: Archiving...'
      archiver_stats = Points::RawData::Archiver.new.call
      puts "  ✓ Archived #{archiver_stats[:archived]} points"
      puts ''

      # Step 2: Verify
      puts '▸ Step 2/3: Verifying...'
      verifier_stats = Points::RawData::Verifier.new.call
      puts "  ✓ Verified #{verifier_stats[:verified]} archives"
      if verifier_stats[:failed].positive?
        puts "  ✗ Failed to verify #{verifier_stats[:failed]} archives"
        puts ''
        puts '⚠ Some archives failed verification. Data NOT cleared for safety.'
        puts 'Please investigate failed archives before running clear_verified.'
        raise "Verification failed for #{verifier_stats[:failed]} archives. Aborting to prevent data loss."
      end
      puts ''

      # Step 3: Clear
      puts '▸ Step 3/3: Clearing verified data...'
      clearer_stats = Points::RawData::Clearer.new.call
      puts "  ✓ Cleared #{clearer_stats[:cleared]} points"
      puts ''

      puts '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
      puts '  ✓ Full Archive Workflow Complete!'
      puts '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
      puts ''
      puts 'Run VACUUM ANALYZE points; to reclaim space.'
    end

    # Alias for backward compatibility
    task initial_archive: :archive
  end
end

def validate_args!(args)
  return if args[:user_id] && args[:year] && args[:month]

  raise 'Usage: rake points:raw_data:TASK[user_id,year,month]'
end
