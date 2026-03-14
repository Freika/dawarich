# frozen_string_literal: true

class Families::Locations
  attr_reader :user

  def initialize(user)
    @user = user
  end

  MAX_POINTS_PER_MEMBER = 5000

  def call
    return [] unless family_feature_enabled?
    return [] unless user.in_family?

    sharing_members = family_members_with_sharing_enabled
    return [] unless sharing_members.any?

    build_family_locations(sharing_members)
  end

  def history(start_at:, end_at:)
    return [] unless family_feature_enabled?
    return [] unless user.in_family?

    sharing_members = family_members_with_sharing_enabled
    return [] unless sharing_members.any?

    build_family_history(sharing_members, start_at: start_at, end_at: end_at)
  end

  private

  def family_feature_enabled?
    DawarichSettings.family_feature_enabled?
  end

  def family_members_with_sharing_enabled
    user.family.members
        .where.not(id: user.id)
        .select(&:family_sharing_enabled?)
  end

  def build_family_locations(sharing_members)
    latest_points =
      sharing_members.map { _1.points.order(timestamp: :desc).first }.compact

    latest_points.map do |point|
      {
        user_id: point.user_id,
        email: point.user.email,
        email_initial: point.user.email.first.upcase,
        latitude: point.lat,
        longitude: point.lon,
        timestamp: point.timestamp.to_i,
        updated_at: Time.zone.at(point.timestamp.to_i),
        battery: point.battery,
        battery_status: point.battery_status
      }
    end
  end

  def build_family_history(sharing_members, start_at:, end_at:)
    sharing_members.filter_map do |member|
      points = member.family_history_points(start_at: start_at, end_at: end_at)
      total = points.count
      next if total.zero?

      sampled = if total > MAX_POINTS_PER_MEMBER
                  nth = (total.to_f / MAX_POINTS_PER_MEMBER).ceil
                  points.where("id IN (SELECT id FROM (#{numbered_rows_sql(points)}) numbered WHERE mod(row_num, #{nth}) = 0)")
                else
                  points
                end

      {
        user_id: member.id,
        email: member.email,
        email_initial: member.email.first.upcase,
        sharing_since: member.family_sharing_started_at&.iso8601,
        points: sampled.pluck(:latitude, :longitude, :timestamp)
      }
    end
  end

  def numbered_rows_sql(scope)
    scope.select('id, ROW_NUMBER() OVER (ORDER BY timestamp ASC) - 1 AS row_num').to_sql
  end
end
