# frozen_string_literal: true

class Points::RawDataLonlatExtractor
  def initialize(point)
    @point = point
  end

  def call
    lonlat = extract_lonlat(@point)

    @point.update(
      longitude: lonlat[0],
      latitude: lonlat[1]
    )
  end

  private

  # rubocop:disable Metrics/MethodLength
  def extract_lonlat(point)
    if point.raw_data.dig('activitySegment', 'waypointPath', 'waypoints', 0)
      # google_semantic_history_parser
      [
        point.raw_data['activitySegment']['waypointPath']['waypoints'][0]['lngE7'].to_f / 10**7,
        point.raw_data['activitySegment']['waypointPath']['waypoints'][0]['latE7'].to_f / 10**7
      ]
    elsif point.raw_data['longitudeE7'] && point.raw_data['latitudeE7']
      # google records
      [
        point.raw_data['longitudeE7'].to_f / 10**7,
        point.raw_data['latitudeE7'].to_f / 10**7
      ]
    elsif point.raw_data.dig('position', 'LatLng')
      # google phone export
      raw_coordinates = point.raw_data['position']['LatLng']
      if raw_coordinates.include?('°')
        raw_coordinates.split(', ').map { _1.chomp('°') }
      else
        raw_coordinates.delete('geo:').split(',')
      end
    elsif point.raw_data['lon'] && point.raw_data['lat']
      # gpx_track_importer, owntracks
      [point.raw_data['lon'], point.raw_data['lat']]
    elsif point.raw_data.dig('geometry', 'coordinates', 0) && point.raw_data.dig('geometry', 'coordinates', 1)
      # geojson
      [
        point.raw_data['geometry']['coordinates'][0],
        point.raw_data['geometry']['coordinates'][1]
      ]
    elsif point.raw_data['longitude'] && point.raw_data['latitude']
      # immich_api, photoprism_api
      [point.raw_data['longitude'], point.raw_data['latitude']]
    end
  end
  # rubocop:enable Metrics/MethodLength
end
