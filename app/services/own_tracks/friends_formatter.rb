# frozen_string_literal: true

class OwnTracks::FriendsFormatter
  BATTERY_STATUS_CODES = {
    'unplugged' => 1,
    'discharging' => 1,
    'charging' => 2,
    'full' => 3
  }.freeze

  BATTERY_STATUS_UNKNOWN = 0

  attr_reader :user

  def initialize(user)
    @user = user
  end

  def call
    members = Families::Locations.new(user).call(excluding: user.id)

    members.flat_map { |member| [card_for(member), location_for(member)] }
  end

  private

  def card_for(member)
    {
      _type: 'card',
      tid: tracker_id(member),
      name: member[:email]
    }.compact
  end

  def location_for(member)
    {
      _type: 'location',
      tid: tracker_id(member),
      lat: member[:latitude],
      lon: member[:longitude],
      tst: member[:timestamp],
      batt: member[:battery],
      bs: BATTERY_STATUS_CODES.fetch(member[:battery_status], BATTERY_STATUS_UNKNOWN)
    }.compact
  end

  def tracker_id(member)
    member[:user_id].to_s(36).upcase
  end
end
