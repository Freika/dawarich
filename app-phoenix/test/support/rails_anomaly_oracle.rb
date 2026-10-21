# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../../../spec', __dir__))
require 'rspec/core'
require File.expand_path('../../../spec/rails_helper', __dir__)

module RailsAnomalyOracle
  def self.cases = @cases ||= []

  def call
    before = Point.where(user_id: @user_id).order(:id).map do |point|
      { id: point.id, timestamp: point.timestamp, longitude: point.lonlat.x, latitude: point.lonlat.y,
        accuracy: point.accuracy, tracker_id: point.tracker_id, velocity: point.velocity,
        vertical_accuracy: point.vertical_accuracy, motion_data: point.motion_data,
        raw_data: point.raw_data, anomaly: point.anomaly, track_id: point.track_id }
    end
    value = super
    RailsAnomalyOracle.cases << { name: RSpec.current_example.full_description, zone: Time.zone.tzinfo.identifier,
               start: @start_time, end: @end_time,
               settings: { 'gps_filtering_enabled' => User.find(@user_id).settings['gps_filtering_enabled'] },
               before:, count: value,
               after: Point.where(user_id: @user_id).order(:id).map do |point|
                 { id: point.id, anomaly: point.anomaly, track_id: point.track_id, motion_data: point.motion_data }
               end }
    value
  end
end

Points::AnomalyFilter.prepend(RailsAnomalyOracle)
result = RSpec::Core::Runner.run(%w[spec/services/points/anomaly_filter_spec.rb
                                    spec/services/points/anomaly_filter_integration_spec.rb
                                    spec/regressions/anomaly_filter_single_point_batches_spec.rb])
raise 'Oracle RSpec failed' unless result.zero?

path = File.expand_path('../fixtures/points/anomaly_filter_rails.json', __dir__)
FileUtils.mkdir_p(File.dirname(path))
File.write(path, JSON.pretty_generate(RailsAnomalyOracle.cases))
puts "Captured #{RailsAnomalyOracle.cases.length} synthetic Rails anomaly-filter calls."
