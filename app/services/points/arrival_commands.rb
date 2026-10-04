# frozen_string_literal: true

module Points
  module ArrivalCommands
    MARKER_TTL = 86_400

    HANDLERS = {
      'points.tile_epoch' => {
        guard: 'TileEpoch.bump writes fresh year tokens; a repeat rotates them again (one extra tile-cache miss)',
        call: lambda { |p|
          timestamps = p.fetch('timestamps')
          ArrivalCommands.for_user(p) { |id| Points::TileEpoch.bump(id, timestamps:) }
        }
      },
      'points.anomaly_filter' => {
        guard: 'AnomalyFilterJob re-evaluates the same range; a repeated enqueue repeats that evaluation',
        call: lambda { |p|
          range = [p.fetch('start_at'), p.fetch('end_at')]
          ArrivalCommands.for_user(p) { |id| Points::AnomalyFilterJob.perform_later(id, *range) }
        }
      },
      'tracks.realtime' => {
        guard: 'Tracks::RealtimeDebouncer#trigger is a debounce claim; a repeat only extends it',
        call: ->(p) { ArrivalCommands.for_user(p) { |id| Tracks::RealtimeDebouncer.new(id).trigger } }
      },
      'tracks.backfill' => {
        guard: 'Per-user SQL union and one cycle publication; legacy Redis ZADD plus SET NX when tables are absent',
        call: lambda { |p|
          timestamps = p.fetch('timestamps')
          ArrivalCommands.for_user(p) { |id| Tracks::BackfillScheduler.new(id, timestamps).call }
        }
      },
      'visits.realtime' => {
        guard: 'Visits::RealtimeDebouncer#trigger is a debounce claim; a repeat only extends it',
        call: ->(p) { ArrivalCommands.for_user(p, zone: true) { |id| Visits::RealtimeDebouncer.new(id).trigger } }
      },
      'points.live_broadcast' => {
        guard: 'at most once: claims live_broadcast:done:<broadcast_id> for a day before broadcasting; ' \
               'a repeat finds it and skips',
        call: lambda { |p|
          marker = "live_broadcast:done:#{p.fetch('broadcast_id')}"
          upserted = p.fetch('upserted')
          payloads = p.fetch('payloads').map(&:symbolize_keys)
          ArrivalCommands.for_user(p, zone: true) do |id|
            next unless PhoenixClaims.claim(marker, MARKER_TTL)

            Points::LiveBroadcaster.new(id, upserted, payloads).call
          end
        }
      }
    }.freeze

    def self.for_user(payload, zone: false)
      user = User.find_by(id: payload.fetch('user_id'))
      return unless user
      return yield(user.id) unless zone

      Time.use_zone(Time.find_zone(user.timezone)) { yield(user.id) }
    end
  end
end
