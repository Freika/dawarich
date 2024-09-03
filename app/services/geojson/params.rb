# frozen_string_literal: true

class Geojson::Params
  attr_reader :json

  def initialize(json)
    @json = json.with_indifferent_access
  end

  def call
    json['features'].map do |point|
      next if point[:geometry].nil? || point.dig(:properties, :timestamp).nil?

      {
        latitude:           point[:geometry][:coordinates][1],
        longitude:          point[:geometry][:coordinates][0],
        battery_status:     point[:properties][:battery_state],
        battery:            battery_level(point[:properties][:battery_level]),
        timestamp:          Time.zone.at(point[:properties][:timestamp]),
        altitude:           point[:properties][:altitude],
        velocity:           point[:properties][:speed],
        tracker_id:         point[:properties][:device_id],
        ssid:               point[:properties][:wifi],
        accuracy:           point[:properties][:horizontal_accuracy],
        vertical_accuracy:  point[:properties][:vertical_accuracy],
        raw_data:           point
      }
    end.compact
  end

  private

  def battery_level(level)
    value = (level.to_f * 100).to_i

    value.positive? ? value : nil
  end
end
