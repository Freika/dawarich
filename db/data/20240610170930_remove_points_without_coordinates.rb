# frozen_string_literal: true

class RemovePointsWithoutCoordinates < ActiveRecord::Migration[7.1]
  def up
    points = Point.where('longitude = 0.0 OR latitude = 0.0')

    Rails.logger.info "Found #{points.count} points without coordinates..."

    points
      .select { |point| point.raw_data['latitudeE7'].nil? && point.raw_data['longitudeE7'].nil? }
      .each(&:destroy)

    Rails.logger.info 'Points without coordinates removed.'

    BulkStatsCalculatingJob.perform_later
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
