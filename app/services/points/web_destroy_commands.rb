# frozen_string_literal: true

module Points
  module WebDestroyCommands
    HANDLERS = {
      'points.web_destroy_follow_up' => {
        guard: 'Repeated delivery rotates epochs and recomputes stats/tracks; achievement scheduling debounces',
        call: ->(payload) { WebDestroyCommands.follow_up(payload) }
      }
    }.freeze

    def self.follow_up(payload)
      user = User.find_by(id: payload.fetch('user_id'), deleted_at: nil)
      return unless user

      Time.use_zone(payload.fetch('timezone')) do
        I18n.with_locale(payload.fetch('locale')) do
          timestamps = payload.fetch('timestamps')
          Points::TileEpoch.bump(user.id, timestamps: timestamps)
          timestamps.map { Time.zone.at(_1) }.map { [_1.year, _1.month] }.uniq.each do |year, month|
            Stats::CalculatingJob.perform_later(user.id, year, month)
          end
          payload.fetch('track_ids').uniq.each { Tracks::RecalculateJob.perform_later(_1) }
          Achievements::CheckJob.schedule(user.id, oldest_timestamp: payload.fetch('oldest_timestamp'))
        end
      end
    end
  end
end
