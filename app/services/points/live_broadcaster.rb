# frozen_string_literal: true

# Broadcasts newly created points to PointsChannel for live map updates.
#
# Since all point creation uses upsert_all (which bypasses ActiveRecord callbacks),
# this service manually broadcasts to PointsChannel after points are created.
#
# Used by real-time point creation services:
# - OwnTracks::PointCreator
# - Overland::PointsCreator
# - Points::Create
#
class Points::LiveBroadcaster
  attr_reader :user_id, :upserted_results, :payloads

  def initialize(user_id, upserted_results, payloads)
    @user_id = user_id
    @upserted_results = upserted_results
    @payloads = payloads
  end

  def call
    return if upserted_results.empty?

    user = User.find_by(id: user_id)
    return unless user&.safe_settings&.live_map_enabled

    payloads_by_timestamp = payloads.index_by { |p| p[:timestamp].to_i }

    upserted_results.each do |result|
      payload = payloads_by_timestamp[result['timestamp'].to_i] || {}

      PointsChannel.broadcast_to(
        user,
        [
          result['latitude'].to_f,
          result['longitude'].to_f,
          payload[:battery].to_s,
          payload[:altitude].to_s,
          result['timestamp'].to_s,
          payload[:velocity].to_s,
          result['id'].to_s,
          '' # country_name not yet available (async geocoding)
        ]
      )
    end
  end
end
