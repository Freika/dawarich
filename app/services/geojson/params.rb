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
    end.flatten
  end

  private

  def process_feature(json)
    case json[:geometry][:type]
    when 'Point'
      build_point(json)
    when 'LineString'
      build_line(json)
    when 'MultiLineString'
      build_multi_line(json)
    end
  end

  def process_feature_collection(json)
    json['features'].map { |feature| process_feature(feature) }
  end

  def build_point(feature)
    {
      latitude:           feature[:geometry][:coordinates][1],
      longitude:          feature[:geometry][:coordinates][0],
      battery_status:     feature[:properties][:battery_state],
      battery:            battery_level(feature[:properties][:battery_level]),
      timestamp:          timestamp(feature),
      altitude:           altitude(feature),
      velocity:           feature[:properties][:speed],
      tracker_id:         feature[:properties][:device_id],
      ssid:               feature[:properties][:wifi],
      accuracy:           feature[:properties][:horizontal_accuracy],
      vertical_accuracy:  feature[:properties][:vertical_accuracy],
      raw_data:           feature
    }
  end

  def build_line(feature)
    feature[:geometry][:coordinates].map do |point|
      build_line_point(feature, point)
    end
  end

  def build_multi_line(feature)
    feature[:geometry][:coordinates].map do |line|
      line.map do |point|
        build_line_point(feature, point)
      end
    end
  end

  def build_line_point(feature, point)
    {
      latitude:  point[1],
      longitude: point[0],
      timestamp: timestamp(point),
      raw_data:  point
    }
  end

  def battery_level(level)
    value = (level.to_f * 100).to_i

    value.positive? ? value : nil
  end

  def altitude(feature)
    feature.dig(:properties, :altitude) || feature.dig(:geometry, :coordinates, 2)
  end

  def timestamp(feature)
    return Time.zone.at(feature[3]) if feature.is_a?(Array)

    value = feature.dig(:properties, :timestamp) || feature.dig(:geometry, :coordinates, 3)
    Time.zone.at(value)
  end
end
