# frozen_string_literal: true

namespace :points do
  desc 'Update points to use lonlat field from latitude and longitude'
  task migrate_to_lonlat: :environment do
    puts 'Updating points to use lonlat...'

    points = Point.where(longitude: nil, latitude: nil)

    points.find_each do |point|
      Points::RawDataLonlatExtractor.new(point).call
    end

    ActiveRecord::Base.connection.execute('REINDEX TABLE points;')

    ActiveRecord::Base.transaction do
      ActiveRecord::Base.connection.execute('ALTER TABLE points DISABLE TRIGGER ALL;')

      # Update the data
      result = ActiveRecord::Base.connection.execute(<<~SQL)
        UPDATE points
        SET lonlat = ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography
        WHERE lonlat IS NULL
          AND longitude IS NOT NULL
          AND latitude IS NOT NULL;
      SQL

      ActiveRecord::Base.connection.execute('ALTER TABLE points ENABLE TRIGGER ALL;')

      puts "Successfully updated #{result.cmd_tuples} points with lonlat values"
    end

    ActiveRecord::Base.connection.execute('ANALYZE points;')
  end
end
