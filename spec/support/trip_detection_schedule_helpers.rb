# frozen_string_literal: true

# Redis is not flushed between examples: clear the debounce key before an
# example asserts that a trigger schedules (or does not schedule) a run.
module TripDetectionScheduleHelpers
  def clear_trip_detection_schedule(user_id)
    Sidekiq.redis { |redis| redis.call('DEL', Trips::DetectJob.schedule_key(user_id)) }
  end
end

RSpec.configure { |config| config.include TripDetectionScheduleHelpers }
