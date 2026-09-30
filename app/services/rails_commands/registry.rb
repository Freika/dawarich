# frozen_string_literal: true

module RailsCommands
  module Registry
    HANDLERS = {
      'visit_months_changed' => {
        guard: 'Rails.cache.delete of the month-summary keys; a repeat deletes nothing more',
        call: lambda { |payload|
          user = User.find_by(id: payload.fetch('user_id'))
          next unless user

          times = payload.fetch('started_at').map { Time.iso8601(_1) }
          Visits::Detection::MachineVisitWipe.bust_month_caches(user, times)
        }
      },
      'airtrail_stats' => {
        guard: 'Converges: each Stats::CalculatingJob recomputes its month from current points and flights ' \
               'under stat.lock!, so a repeat enqueues the same months again; the cost is one more recalculation ' \
               'and cache invalidation per month, which every Rails AirTrail sync already pays',
        call: ->(payload) { AirTrail::StatsFollowUp.call(payload) }
      },
      'tracks_changed' => {
        guard: 'bump_range writes fresh tokens again (one extra tile-cache miss); broadcasts re-read current ' \
               'rows, and the only subscriber ignores the payload and debounces one tile refresh',
        call: lambda { |payload|
          user_id = payload.fetch('user_id')
          created = payload.fetch('created')
          Tracks::TileEpoch.bump_range(user_id, payload.fetch('min_ts'), payload.fetch('max_ts'))
          Track.where(id: created + payload.fetch('updated')).find_each do |track|
            track.broadcast_track_update(created.include?(track.id) ? 'created' : 'updated')
          end
          Track.broadcast_destroyed(payload.fetch('destroyed').map { [_1, user_id] })
        }
      },
      'tracks_generate_range' => {
        guard: 'A second ParallelGeneratorJob over the same fixed window re-cleans it under the user lock, and ' \
               'both passes claim only orphan points (unique time-span index), so tracks converge; the cost ' \
               'is one duplicate generation pass, the whole history for a self-hosted user with no tracks',
        call: lambda { |payload|
          Tracks::ParallelGeneratorJob.perform_later(payload.fetch('user_id'),
                                                     **Tracks::GenerationCommand.job_options(payload))
        }
      },
      'tracks_throttled_backfill' => {
        guard: 'ThrottledBackfillJob.schedule is SET NX on track_throttled_backfill:user:<id> (12 h, 7 days ' \
               'after completion); a repeat finds the key and enqueues nothing',
        call: lambda { |payload|
          user = User.find_by(id: payload.fetch('user_id'))
          Tracks::ThrottledBackfillJob.schedule(user) if user
        }
      },
      'tracks_realtime_retrigger' => {
        guard: 'RealtimeDebouncer#trigger is SET NX: a repeat extends the 2 min TTL, or, once the job cleared ' \
               'the key, schedules one more RealtimeGenerationJob, which claims only untracked points ' \
               'under the user lock',
        call: ->(payload) { Tracks::RealtimeDebouncer.new(payload.fetch('user_id')).trigger }
      },
      'geocode_recent_points' => {
        guard: 'async_reverse_geocode claims geocode:enq:Point:<id> with SET NX over not_reverse_geocoded ' \
               'points, so queued and finished points are skipped; a point whose job raised may cost one ' \
               'more provider lookup',
        call: lambda { |payload|
          user = User.find_by(id: payload.fetch('user_id'))
          Tracks::RealtimeGeocodeFollowUp.call(user, since: Time.zone.at(payload.fetch('since'))) if user
        }
      },
      'transport_progress' => {
        guard: 'SET NX on transport_progress:<event_id> (unless_exist, the status CACHE_TTL) before ' \
               'increment_processed!; event_id is the forwarded ReclassifyTrackJob id, one per track per run, ' \
               'so a repeat finds the key and counts nothing',
        call: lambda { |payload|
          key = "transport_progress:#{payload.fetch('event_id')}"
          ttl = Tracks::TransportationRecalculationStatus::CACHE_TTL
          next unless Rails.cache.write(key, 1, unless_exist: true, expires_in: ttl)

          Tracks::TransportationRecalculationStatus.new(payload.fetch('user_id')).increment_processed!
        }
      },
      'exports.points_created' => {
        guard: 'Re-produces exports.points only while the export is still created: ExportJob claims ' \
               'created -> processing by compare-and-set and the outbox keeps one pending points-export:<id>',
        call: lambda { |payload|
          export = Export.find_by(id: payload.fetch('export_id'), user_id: payload.fetch('user_id'))
          next unless export&.created?

          I18n.with_locale(payload.fetch('locale')) do
            JobCommands.produce('exports.points', { 'export_id' => export.id, 'user_id' => export.user_id },
                                aggregate_id: export.id, producer: 'Phoenix ExportsCreate',
                                dedupe_key: "points-export:#{export.id}")
          end
        }
      }
    }.merge(Points::ArrivalCommands::HANDLERS).freeze

    module_function

    def handler(kind) = HANDLERS.dig(kind, :call)
  end
end
