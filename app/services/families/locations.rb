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
    DawarichSettings.family_feature_enabled?
  end

  def family_members_with_sharing_enabled
    user.family.members
        .where.not(id: user.id)
        .select(&:family_sharing_enabled?)
  end

  def build_family_locations(sharing_members)
    latest_points = sharing_members.map { |member| member.points.last }.compact

    latest_points.map do |point|
      next unless point

      {
        user_id: point.user_id,
        email: point.user.email,
        email_initial: point.user.email.first.upcase,
        latitude: point.lat.to_f,
        longitude: point.lon.to_f,
        timestamp: point.timestamp.to_i,
        updated_at: Time.at(point.timestamp.to_i)
      }
    end.compact
  end
end
