# frozen_string_literal: true

class Families::Locations
  attr_reader :user

  def initialize(user)
    @user = user
  end

  def call
    return [] unless family_feature_enabled?
    return [] unless user.in_family?

    sharing_members = family_members_with_sharing_enabled
    return [] unless sharing_members.any?

    build_family_locations(sharing_members)
  end

  private

  def family_feature_enabled?
    user.family_feature_available?
  end

  def family_members_with_sharing_enabled
    user.family.members
        .where.not(id: user.id)
        .select(&:family_sharing_enabled?)
  end

  def build_family_locations(sharing_members)
    latest_points =
      sharing_members.map { _1.points.last }.compact

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
end
