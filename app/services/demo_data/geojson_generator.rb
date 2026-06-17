# frozen_string_literal: true

class DemoData::GeojsonGenerator
  DEFAULT_FIXTURE_PATH = Rails.root.parent.join('e2e-dawarich-playwright/fixtures/demo_data.json').to_s

  def initialize(base_time: nil)
    @base_time = base_time
  end

  def call
    data = Oj.load(File.read(fixture_path))
    features = data['features']

    shift_timestamps!(features)

    Oj.dump(data, mode: :compat)
  end

  private

  def fixture_path
    path = ENV.fetch('E2E_DEMO_DATA', DEFAULT_FIXTURE_PATH)
    return path if File.exist?(path)

    raise "e2e demo fixture not found at #{path} — set E2E_DEMO_DATA to demo_data.json in the e2e repo"
  end

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
