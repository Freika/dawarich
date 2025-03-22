# frozen_string_literal: true

namespace :points do
  desc 'Update points to use lonlat field from latitude and longitude'
  task migrate_to_lonlat: :environment do
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
