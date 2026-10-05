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
        call: ->(payload) { Tracks::BackfillCommands.reverse_walk(payload) }
      },
      'tracks_realtime_retrigger' => {
        guard: 'RealtimeDebouncer#trigger is a debounce claim: a repeat extends it by 2 min, or, once the job ' \
               'cleared it, schedules one more RealtimeGenerationJob, which claims only untracked points ' \
               'under the user lock',
        call: ->(payload) { Tracks::RealtimeDebouncer.new(payload.fetch('user_id')).trigger }
      },
      'geocode_recent_points' => {
        guard: 'async_reverse_geocode claims geocode:enq:Point:<id> once over not_reverse_geocoded ' \
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
      'schedule_untracked_tracks' => {
        guard: 'untracked-only generation over the import range; a repeat finds no untracked point to claim',
        call: ->(payload) { Import.find_by(id: payload.fetch('import_id'))&.schedule_untracked_track_generation }
      },
      'enhanced_import_card' => {
        guard: 'broadcast_replace of the card as it is now; a repeat re-renders the same state',
        call: lambda { |payload|
          import = Import.find_by(id: payload.fetch('import_id'))
          EnhancedImport::CardBroadcaster.call(import) if import
        }
      },
      'places_delete_if_orphan' => {
        guard: 'Places::DeleteIfOrphan re-checks every reference before deleting; ' \
               'a repeat finds the place kept or gone',
        call: lambda { |payload|
          Points::ArrivalCommands.for_user(payload) do
            ActiveJob.perform_all_later(payload.fetch('place_ids').map { |id| Places::DeleteIfOrphanJob.new(id) })
          end
        }
      },
      'place_name_fetch' => {
        guard: 'Places::NameFetcher names the place from the provider; a repeat repeats a rate-limited lookup',
        call: lambda { |payload|
          Points::ArrivalCommands.for_user(payload) { Places::NameFetchingJob.perform_later(payload.fetch('place_id')) }
        }
      },
      'reverse_geocode_place' => {
        guard: 'place reverse geocoding converges (Finding 5); a repeat rewrites the same values',
        call: lambda { |payload|
          place_id = payload.fetch('place_id')
          Points::ArrivalCommands.for_user(payload) { ReverseGeocodingJob.perform_later('place', place_id) }
        }
      },
      'imports.progress' => {
        guard: 'Re-renders the current owner-scoped import row; repeats never restore an old processed count',
        call: lambda { |payload|
          import = Import.find_by(id: payload.fetch('import_id'), user_id: payload.fetch('user_id'))
          next unless import

          I18n.with_locale(payload.fetch('locale')) do
            Turbo::StreamsChannel.broadcast_replace_to(
              [import.user, :imports], target: ActionView::RecordIdentifier.dom_id(import),
              partial: 'imports/table_row', locals: { import: import, timezone: import.user.safe_settings.timezone }
            )
          end
        }
      },
      'exports.points_created' => {
        guard: 'Re-produces exports.points only while the export is still created: ExportJob claims ' \
               'created -> processing by compare-and-set and the outbox keeps one pending points-export:<id>',
        call: lambda { |payload|
          export = Export.find_by(id: payload.fetch('export_id'), user_id: payload.fetch('user_id'))
          next unless export&.created?

          produce = lambda {
            I18n.with_locale(payload.fetch('locale')) do
              JobCommands.produce('exports.points', { 'export_id' => export.id, 'user_id' => export.user_id },
                                  aggregate_id: export.id, producer: 'Phoenix ExportsCreate',
                                  dedupe_key: "points-export:#{export.id}")
            end
          }

          begin
            Time.use_zone(export.user.timezone, &produce)
          rescue ArgumentError
            produce.call
          end
        }
      },
      'family_location_request_mail' => {
        guard: 'SET NX on family_location_request_mail:<request_id> (one day) before deliver_later, deleted ' \
               'again when the enqueue raises; a repeat finds the key and enqueues no second mail, and a cache ' \
               'that cannot claim the key raises so the poller retries',
        call: lambda { |payload|
          request = Family::LocationRequest.find_by(id: payload.fetch('request_id'))
          next unless request&.requester

          key = "family_location_request_mail:#{request.id}"
          unless Rails.cache.write(key, 1, unless_exist: true, expires_in: 1.day)
            next if Rails.cache.exist?(key)

            raise 'the cache could not claim the family location request mail'
          end

          enqueue = -> { FamilyMailer.location_request(request).deliver_later }
          begin
            begin
              Time.use_zone(request.requester.timezone, &enqueue)
            rescue ArgumentError
              enqueue.call
            end
          rescue StandardError
            Rails.cache.delete(key)
            raise
          end
        }
      },
      'release_reclassify_tracks' => {
        guard: "ReclassifyTrackJob replaces a track's inferred segments in one transaction; " \
               'a repeat enqueue reclassifies the same track to the same result',
        call: lambda { |payload|
          at = Time.zone.at(payload.fetch('run_at'))
          jobs = payload.fetch('track_ids').map do |track_id|
            TransportationModes::ReclassifyTrackJob.new(track_id).tap { _1.scheduled_at = at }
          end
          ActiveJob.perform_all_later(jobs)
        }
      },
      'release_user_redetect' => {
        guard: 'Visits::UserRedetectJob recomputes machine visits month by month under the per-user lock; ' \
               'a repeat produces the same visits',
        call: lambda { |payload|
          Visits::UserRedetectJob.set(wait_until: Time.zone.at(payload.fetch('run_at')))
                                 .perform_later(payload.fetch('user_id'))
        }
      },
      'release_null_island_follow_up' => {
        guard: 'follow_up re-reads the null-island rows: a repeat bumps the tile epoch again, finds no visit left ' \
               'to destroy and re-enqueues convergent stats and track recalculations',
        call: lambda { |payload|
          user = User.find_by(id: payload.fetch('user_id'))
          DataMigrations::CleanupNullIslandJob.follow_up(user) if user
        }
      }
    }.merge(Points::ArrivalCommands::HANDLERS)
     .merge(Points::WebDestroyCommands::HANDLERS)
     .merge(Points::AnomalyFilterCommands::HANDLERS)
     .merge(Imports::PostprocessingCommands::HANDLERS)
     .merge(Imports::UploadCommands::HANDLERS)
     .merge(Imports::DownloadCommands::HANDLERS)
     .merge(Imports::PreparedDownloadPurgeCommands::HANDLERS)
     .merge(Imports::DestroyCommands::HANDLERS)
     .merge(Imports::ExtractionCommands::HANDLERS)
     .merge(RailsCommands::ShareManagementCommands::HANDLERS)
     .merge(Posters::CreationCommand::HANDLERS)
     .merge(Posters::PurgeCommands::HANDLERS)
     .merge(Posters::ProgressCommands::HANDLERS)
     .merge(A8Handlers::HANDLERS)
     .merge(Integrations::SchedulingCommands::HANDLERS)
     .merge(Families::JobCommands::HANDLERS)
     .merge(Places::JobCommands::HANDLERS)
     .merge(
       'imports.resume' => {
         guard: 'Durable event receipt and per-import lease; repeats cannot restart a completed receipt',
         call: ->(payload) { Imports::GpxResume.call(payload) }
       }
     ).merge(
       'imports.normal_resume' => {
         guard: 'Durable event receipt and per-import lease; completed receipts do not restart imports',
         call: ->(payload) { Imports::NormalResume.call(payload) }
       }
     ).merge(Stats::Commands::HANDLERS).merge(Users::Digests::Commands::HANDLERS).freeze

    module_function

    def handler(kind) = HANDLERS.dig(kind, :call)
  end
end
