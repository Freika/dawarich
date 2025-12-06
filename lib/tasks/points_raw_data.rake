# frozen_string_literal: true

namespace :points do
  namespace :raw_data do
    desc 'Restore raw_data from archive to database for a specific month'
    task :restore, [:user_id, :year, :month] => :environment do |_t, args|
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
    task :restore_temporary, [:user_id, :year, :month] => :environment do |_t, args|
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
      total_points = Point.count
      archived_points = Point.where(raw_data_archived: true).count
      percentage = total_points.positive? ? (archived_points.to_f / total_points * 100).round(2) : 0

      puts "Archives: #{total_archives}"
      puts "Points archived: #{archived_points} / #{total_points} (#{percentage}%)"
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

    desc 'Verify archive integrity for a month'
    task :verify, [:user_id, :year, :month] => :environment do |_t, args|
      validate_args!(args)

      user_id = args[:user_id].to_i
      year = args[:year].to_i
      month = args[:month].to_i

      puts '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
      puts '  Verifying Archives'
      puts "  User: #{user_id} | Month: #{year}-#{format('%02d', month)}"
      puts '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
      puts ''

      archives = Points::RawDataArchive.for_month(user_id, year, month)

      if archives.empty?
        puts 'No archives found.'
        exit
      end

      all_ok = true

      archives.each do |archive|
        print "Chunk #{archive.chunk_number}: "

        # Check file attached
        unless archive.file.attached?
          puts '✗ ERROR - File not attached!'
          all_ok = false
          next
        end

        # Download and count
        begin
          compressed = archive.file.blob.download
          io = StringIO.new(compressed)
          gz = Zlib::GzipReader.new(io)

          actual_count = 0
          gz.each_line { actual_count += 1 }
          gz.close

          if actual_count == archive.point_count
            puts "✓ OK (#{actual_count} points, #{archive.size_mb} MB)"
          else
            puts "✗ MISMATCH - Expected #{archive.point_count}, found #{actual_count}"
            all_ok = false
          end
        rescue StandardError => e
          puts "✗ ERROR - #{e.message}"
          all_ok = false
        end
      end

      puts ''
      if all_ok
        puts '✓ All archives verified successfully!'
      else
        puts '✗ Some archives have issues. Please investigate.'
      end
    end

    desc 'Run initial archival for old data (safe to re-run)'
    task initial_archive: :environment do
      puts '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
      puts '  Initial Archival (2+ months old data)'
      puts '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
      puts ''
      puts 'This will archive points.raw_data for months 2+ months old.'
      puts 'This is safe to run multiple times (idempotent).'
      puts ''
      print 'Continue? (y/N): '

      response = $stdin.gets.chomp.downcase
      unless response == 'y'
        puts 'Cancelled.'
        exit
      end

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
      puts '1. Verify a sample: rake points:raw_data:verify[user_id,year,month]'
      puts '2. Check stats: rake points:raw_data:status'
      puts '3. (Optional) Reclaim space: VACUUM FULL points; (during maintenance)'
    end
  end
end

def validate_args!(args)
  return if args[:user_id] && args[:year] && args[:month]

  raise 'Usage: rake points:raw_data:TASK[user_id,year,month]'
end
