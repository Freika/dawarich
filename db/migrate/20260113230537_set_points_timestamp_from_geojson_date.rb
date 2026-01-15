# frozen_string_literal: true

class SetPointsTimestampFromGeojsonDate < ActiveRecord::Migration[8.0]
  def change
    Point.where(timestamp: nil).find_each do |point|
      geojson = point.raw_data

      next unless geojson && geojson['properties'] && geojson['properties']['date']

      begin
        parsed_time = Time.zone.parse(geojson['properties']['date']).utc.to_i

        point.update!(timestamp: parsed_time)
      rescue ArgumentError => e
        Rails.logger.warn("Failed to parse date for Point ID #{point.id}: #{e.message}")
      end
    end
  end
end
