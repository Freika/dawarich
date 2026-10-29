# frozen_string_literal: true

class Points::MarkValid
  def self.call(user:, point_id:)
    new(user, point_id).call
  end

  def initialize(user, point_id)
    @user = user
    @point_id = point_id
  end

  def call
    point = user.points.find(point_id)
    point.update_columns(anomaly: false, anomaly_override: true, updated_at: Time.current)
    Tracks::OrphanPointAttacher.new(user, [point], neighbours(point)).call

    Points::TileEpoch.bump(user.id, timestamps: [point.timestamp])
    enqueue_stats_recalculation(point)
    Achievements::CheckJob.schedule(user.id, oldest_timestamp: point.timestamp)
    point.reload
  end

  private

  attr_reader :user, :point_id

  def neighbours(point)
    window = user.safe_settings.minutes_between_routes.to_i.minutes.to_i
    user.points.not_anomaly
        .where(timestamp: (point.timestamp - window)..(point.timestamp + window))
        .order(:timestamp, :id).to_a
  end

  def enqueue_stats_recalculation(point)
    local_time = Time.zone.at(point.timestamp).in_time_zone(user.timezone_iana)
    Stats::CalculatingJob.perform_later(user.id, local_time.year, local_time.month)
  end
end
