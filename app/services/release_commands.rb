# frozen_string_literal: true

module ReleaseCommands
  COMMANDS = {
    'release.point_dimensions_country' => {
      version: 1,
      sidekiq: lambda { |payload, at|
        if payload.fetch('phase') == 'dimensions'
          later(DataMigrations::BackfillPointDimensionsJob, at, payload['start_id'], payload.fetch('batch_size'))
        else
          later(DataMigrations::BackfillPointCountryIdJob, at, payload['start_id'], payload.fetch('batch_size'),
                repair_collisions: payload.fetch('repair_collisions'))
        end
      }
    },
    'release.route_opacity' => {
      version: 1, sidekiq: ->(_payload, at) { later(DataMigrations::FixRouteOpacityJob, at) }
    },
    'release.onboarding_completed' => {
      version: 1, sidekiq: ->(_payload, at) { later(DataMigrations::BackfillOnboardingCompletedJob, at) }
    },
    'release.orphaned_tracks' => {
      version: 1, sidekiq: ->(_payload, at) { later(DataMigrations::DestroyOrphanedTracksJob, at) }
    },
    'release.tracks_dedup' => {
      version: 1, sidekiq: ->(payload, at) { later(Tracks::DeduplicationJob, at, payload.fetch('user_id')) }
    },
    'release.place_name_locks' => {
      version: 1, sidekiq: ->(_payload, at) { later(DataMigrations::BackfillPlaceNameLocksJob, at) }
    },
    'release.time_anchor' => {
      version: 1, sidekiq: ->(payload, at) { later(TrackSegments::TimeAnchorBackfillJob, at, payload.fetch('from_id')) }
    },
    'release.transportation' => {
      version: 1,
      sidekiq: lambda { |payload, at|
        job = if payload.fetch('scope') == 'all'
                TransportationModes::FleetReclassifyJob
              else
                DataMigrations::BackfillTransportationModesJob
              end
        later(job, at, payload.fetch('from_track_id'))
      }
    },
    'release.visits_fleet_redetect' => {
      version: 1, sidekiq: ->(_payload, at) { later(Visits::FleetRedetectJob, at) }
    },
    'release.null_island' => {
      version: 1, sidekiq: ->(payload, at) { later(DataMigrations::CleanupNullIslandJob, at, payload['user_id']) }
    },
    'release.motion_data' => {
      version: 1,
      sidekiq: lambda { |payload, at|
        later(DataMigrations::BackfillMotionDataJob, at, batch_size: payload.fetch('batch_size'))
      }
    },
    'release.altitude' => {
      version: 1, sidekiq: ->(_payload, at) { later(DataMigrations::BackfillAltitudeJob, at) }
    }
  }.freeze

  module_function

  def later(job, at, *args, **kwargs)
    JobCommands.enqueue_after_commit(nil) { job.set(wait_until: at).perform_later(*args, **kwargs) }
  end

  def forwarded?(job, type, payload, aggregate_id: nil)
    return false unless JobOwnership.oban?("command:#{type}")

    JobCommands.forward(type, payload, event_id: job.job_id, aggregate_id:, producer: job.class.name)
    true
  end
end
