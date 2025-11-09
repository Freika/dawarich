# frozen_string_literal: true

class OwnTracks::FamilyLocationsFormatter
  attr_reader :user

  def initialize(user)
    @user = user
  end

  def call
    return [] unless family_feature_enabled?
    return [] unless user.in_family?

    sharing_members = family_members_with_sharing_enabled
    return [] unless sharing_members.any?

    latest_points = sharing_members.map { |member| member.points.order(timestamp: :desc).first }.compact
    latest_points.map { |point| build_owntracks_location(point) }.compact
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

  def build_owntracks_location(point)
    location = {
      _type: 'location',
      lat: point.lat.to_f,
      lon: point.lon.to_f,
      tst: point.timestamp.to_i,
      tid: point.user.email,
      acc: point.accuracy,
      alt: point.altitude,
      batt: point.battery,
      bs: OwnTracks::Params.battery_status_to_numeric(point.battery_status),
      # t: OwnTracks::Params.trigger_to_string(point.trigger),
      vel: OwnTracks::Params.velocity_to_kmh(point.velocity),
      conn: OwnTracks::Params.connection_to_string(point.connection),
    }

    location
  end
end

