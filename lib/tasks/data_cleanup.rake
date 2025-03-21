require 'csv'

namespace :data_cleanup do
  desc 'Remove duplicate points using raw SQL and export them to a file'
  task remove_duplicate_points: :environment do
    timestamp = Time.current.strftime('%Y%m%d%H%M%S')
    export_path = Rails.root.join("tmp/duplicate_points_#{timestamp}.csv")
    connection = ActiveRecord::Base.connection

    puts 'Finding duplicates...'

    # First create temp tables for each duplicate type separately
    connection.execute(<<~SQL)
      DROP TABLE IF EXISTS lat_long_duplicates;
      CREATE TEMPORARY TABLE lat_long_duplicates AS
      SELECT id
      FROM (
        SELECT id,
               ROW_NUMBER() OVER (PARTITION BY latitude, longitude, timestamp, user_id ORDER BY id) as row_num
        FROM points
      ) AS dups
      WHERE dups.row_num > 1;
    SQL

    connection.execute(<<~SQL)
      DROP TABLE IF EXISTS lonlat_duplicates;
      CREATE TEMPORARY TABLE lonlat_duplicates AS
      SELECT id
      FROM (
        SELECT id,
               ROW_NUMBER() OVER (PARTITION BY lonlat, timestamp, user_id ORDER BY id) as row_num
        FROM points
      ) AS dups
      WHERE dups.row_num > 1;
    SQL

    # Then create the combined duplicates table
    connection.execute(<<~SQL)
      DROP TABLE IF EXISTS duplicate_points;
      CREATE TEMPORARY TABLE duplicate_points AS
      SELECT id FROM lat_long_duplicates
      UNION
      SELECT id FROM lonlat_duplicates;
    SQL

    # Count duplicates
    duplicate_count = connection.select_value('SELECT COUNT(*) FROM duplicate_points').to_i
    puts "Found #{duplicate_count} duplicate points"

    if duplicate_count > 0
      # Export duplicates to CSV
      puts "Exporting duplicates to #{export_path}..."

      columns = connection.select_values("SELECT column_name FROM information_schema.columns WHERE table_name = 'points' ORDER BY ordinal_position")

      CSV.open(export_path, 'wb') do |csv|
        # Write headers
        csv << columns

        # Export data in batches to avoid memory issues
        offset = 0
        batch_size = 1000

        loop do
          sql = <<~SQL
            SELECT #{columns.join(',')}
            FROM points
            WHERE id IN (SELECT id FROM duplicate_points)
            ORDER BY id
            LIMIT #{batch_size} OFFSET #{offset};
          SQL

          records = connection.select_all(sql)
          break if records.empty?

          records.each do |record|
            csv << columns.map { |col| record[col] }
          end

          offset += batch_size
          print '.' if (offset % 10_000).zero?
        end
      end

      puts "\nSuccessfully exported #{duplicate_count} duplicate points to #{export_path}"

      # Delete the duplicates
      deleted_count = connection.execute(<<~SQL)
        DELETE FROM points
        WHERE id IN (SELECT id FROM duplicate_points);
      SQL

      puts "Successfully deleted #{deleted_count.cmd_tuples} duplicate points"

      # Clean up
      connection.execute('DROP TABLE IF EXISTS lat_long_duplicates;')
      connection.execute('DROP TABLE IF EXISTS lonlat_duplicates;')
      connection.execute('DROP TABLE IF EXISTS duplicate_points;')
    else
      puts 'No duplicate points to remove'
    end
  end

  desc 'Update points to use lonlat field from latitude and longitude'
  task update_points_to_use_lonlat: :environment do
    puts 'Updating points to use lonlat...'

    # Use PostGIS functions to properly create geography type
    result = ActiveRecord::Base.connection.execute(<<~SQL)
      UPDATE points
      SET lonlat = ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography
      WHERE lonlat IS NULL
        AND longitude IS NOT NULL
        AND latitude IS NOT NULL;
    SQL

    puts "Successfully updated #{result.cmd_tuples} points with lonlat values"
  end
end
