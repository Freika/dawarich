# frozen_string_literal: true

class Points::OutlierDetectionJob < ApplicationJob
  queue_as :default

  def perform(user_id, start_at = nil, end_at = nil)
    user = find_user_or_skip(user_id) || return
    return unless user.safe_settings.outlier_detection_enabled?

    parsed_start = start_at ? Time.zone.parse(start_at.to_s) : nil
    parsed_end = end_at ? Time.zone.parse(end_at.to_s) : nil

    count = Points::OutlierDetector.new(user, start_at: parsed_start, end_at: parsed_end).call

    Rails.logger.info(
      "#{self.class.name}: Flagged #{count} outlier points for user #{user_id}"
    )
  end
end
