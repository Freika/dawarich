# frozen_string_literal: true

class DemoData::GeojsonGenerator
  FIXTURE_PATH = Rails.root.join('lib/assets/demo_data.json')

  def initialize(base_time: nil)
    @base_time = base_time
  end

  def call
    data = Oj.load(File.read(FIXTURE_PATH))
    features = data['features']

    shift_timestamps!(features)

    Oj.dump(data, mode: :compat)
  end

  private

  def shift_timestamps!(features)
    return if features.empty?

    original_timestamps = features.map { |f| f['properties']['timestamp'] }
    original_end = original_timestamps.max

    # Shift so the last point lands at the current time
    target_end = (@base_time || Time.current).to_i
    offset = target_end - original_end

    features.each do |feature|
      feature['properties']['timestamp'] += offset
    end
  end
end
