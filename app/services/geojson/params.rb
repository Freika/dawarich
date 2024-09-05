# frozen_string_literal: true

class Geojson::Params
  attr_reader :json

  def initialize(json)
    @json = json.with_indifferent_access
  end

  def call
    case json['type']
    when 'Feature' then process_feature(json)
    when 'FeatureCollection' then process_feature_collection(json)
    end
  end

  private

  def process_feature(json)
    json['features'].map do |point|
      next if point[:geometry].nil? || point.dig(:properties, :timestamp).nil?

      build_point(point)
    end.compact
  end

  def process_feature_collection(json)
    json['features'].map { |feature| process_feature(feature) }
  end

  def build_point(point)
    {
      latitude:           point[:geometry][:coordinates][1],
      longitude:          point[:geometry][:coordinates][0],
      battery_status:     point[:properties][:battery_state],
      battery:            battery_level(point[:properties][:battery_level]),
      timestamp:          timestamp(point),
      altitude:           altitude(point),
      velocity:           point[:properties][:speed],
      tracker_id:         point[:properties][:device_id],
      ssid:               point[:properties][:wifi],
      accuracy:           point[:properties][:horizontal_accuracy],
      vertical_accuracy:  point[:properties][:vertical_accuracy],
      raw_data:           point
    }
  end

  def battery_level(level)
    value = (level.to_f * 100).to_i

    value.positive? ? value : nil
  end

  def altitude(point)
    point.dig(:properties, :altitude) || point.dig(:geometry, :coordinates, 2)
  end

  def timestamp(point)
    value = point.dig(:properties, :timestamp) || point.dig(:geometry, :coordinates, 3)

    Time.zone.at(value)
  end
end
