# frozen_string_literal: true

class Users::ImportData::Tracks
  # Allowlist of Track columns the importer is permitted to set from the
  # user-supplied JSON. Anything else (user_id, id, created_at, updated_at,
  # arbitrary unknown columns) is silently dropped to prevent the import
  # archive from transferring the track to another user, rewriting its id,
  # or backdating its timestamps.
  IMPORTABLE_ATTRIBUTES = %w[
    start_at end_at original_path distance avg_speed duration
    elevation_gain elevation_loss elevation_max elevation_min dominant_mode
  ].freeze

  # Refresh deliberately excludes start_at/end_at: by the time we're in the
  # refresh path we've already matched the existing row by those columns via
  # the unique index, and letting the import payload shift them on a precision
  # or timezone drift would silently break subsequent lookups.
  REFRESHABLE_ATTRIBUTES = (IMPORTABLE_ATTRIBUTES - %w[start_at end_at]).freeze

  def initialize(user, tracks_data)
    @user = user
    @tracks_data = tracks_data
  end

  def call
    return 0 unless tracks_data.is_a?(Array)

    Rails.logger.info "Importing #{tracks_data.size} tracks for user: #{user.email}"

    tracks_created = 0
    tracks_updated = 0
    tracks_skipped_existing = 0
    tracks_failed_refresh = 0

    tracks_data.each do |track_data|
      next unless track_data.is_a?(Hash)

      existing_track = find_existing_track(track_data)

      if existing_track
        Rails.logger.debug "Track already exists: #{track_data['start_at']}"
        tracks_skipped_existing += 1
        next
      end

      begin
        track_record = create_track_record(track_data)
        create_segments(track_record, track_data['segments']) if track_data['segments'].present?
        tracks_created += 1
      rescue ActiveRecord::RecordNotUnique
        if refresh_existing_track(track_data)
          tracks_updated += 1
        else
          tracks_failed_refresh += 1
        end
        next
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.error "Failed to create track: #{e.message}"
        ExceptionReporter.call(e, 'Failed to create track during import')
        next
      rescue StandardError => e
        Rails.logger.error "Unexpected error creating track: #{e.message}"
        ExceptionReporter.call(e, 'Unexpected error during track import')
        next
      end
    end

    Rails.logger.info(
      'Tracks import completed. ' \
      "Created: #{tracks_created}, Updated: #{tracks_updated}, " \
      "Skipped (already exists): #{tracks_skipped_existing}, " \
      "Failed refresh: #{tracks_failed_refresh}"
    )
    tracks_created
  end

  private

  attr_reader :user, :tracks_data

  # Pre-check: matches on (start_at, end_at, distance) so re-imports with
  # the *same* metadata short-circuit before hitting the DB. The unique index
  # on (user_id, start_at, end_at) catches the case where distance differs;
  # `refresh_existing_track` then updates the existing row.
  def find_existing_track(track_data)
    user.tracks.find_by(
      start_at: track_data['start_at'],
      end_at: track_data['end_at'],
      distance: track_data['distance']
    )
  end

  # Looks up by the unique-index columns (no distance), so a re-import with
  # a different distance for the same time window finds the existing row.
  def find_track_in_window(track_data)
    user.tracks.find_by(
      start_at: track_data['start_at'],
      end_at: track_data['end_at']
    )
  end

  # Called on RecordNotUnique: the unique index blocked our insert because a
  # track with the same (user_id, start_at, end_at) already exists. Refresh
  # its attributes from the import data so re-imports with recomputed
  # distance/path/duration aren't silently dropped on the floor.
  def refresh_existing_track(track_data)
    existing = find_track_in_window(track_data)
    unless existing
      Rails.logger.warn(
        'event=tracks.unique_violation_rescued service=import_data action=skipped ' \
        "user_id=#{user.id} start_at=#{track_data['start_at']} end_at=#{track_data['end_at']} " \
        'reason=race_winner_not_found'
      )
      return false
    end

    ActiveRecord::Base.transaction(requires_new: true) do
      existing.update!(track_data.slice(*REFRESHABLE_ATTRIBUTES))

      if track_data['segments'].present?
        existing.track_segments.delete_all
        create_segments(existing, track_data['segments'])
      end
    end

    Rails.logger.info(
      'event=tracks.unique_violation_rescued service=import_data action=updated ' \
      "user_id=#{user.id} track_id=#{existing.id} " \
      "start_at=#{track_data['start_at']} end_at=#{track_data['end_at']}"
    )
    true
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
    # The outer `rescue` at #call already fired for the original `create!`
    # collision; a second exception of the same type raised from inside this
    # method (e.g. validation failure on `update!`, or a fresh `RecordNotUnique`
    # if the payload's start_at/end_at somehow collide with another row) is
    # NOT re-caught by that outer handler. Catch it locally and return false
    # so #call records this row as a failed refresh and keeps iterating.
    Rails.logger.error(
      'event=tracks.unique_violation_rescued service=import_data action=update_failed ' \
      "user_id=#{user.id} track_id=#{existing&.id} " \
      "start_at=#{track_data['start_at']} end_at=#{track_data['end_at']} " \
      "error=#{e.class}: #{e.message}"
    )
    ExceptionReporter.call(e, 'Failed to refresh existing track during import')
    false
  end

  def create_track_record(track_data)
    user.tracks.create!(track_data.slice(*IMPORTABLE_ATTRIBUTES))
  end

  def create_segments(track, segments_data)
    return unless segments_data.is_a?(Array)

    segments_data.each do |segment_data|
      next unless segment_data.is_a?(Hash)

      track.track_segments.create!(segment_data)
    end
  end
end
