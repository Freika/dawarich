# frozen_string_literal: true

class Users::ImportData::Tracks
  def initialize(user, tracks_data)
    @user = user
    @tracks_data = tracks_data
  end

  def call
    return 0 unless tracks_data.is_a?(Array)

    Rails.logger.info "Importing #{tracks_data.size} tracks for user: #{user.email}"

    tracks_created = 0

    tracks_data.each do |track_data|
      next unless track_data.is_a?(Hash)

      existing_track = find_existing_track(track_data)

      if existing_track
        Rails.logger.debug "Track already exists: #{track_data['start_at']}"
        next
      end

      begin
        track_record = create_track_record(track_data)
        create_segments(track_record, track_data['segments']) if track_data['segments'].present?
        tracks_created += 1
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

    Rails.logger.info "Tracks import completed. Created: #{tracks_created}"
    tracks_created
  end

  private

  attr_reader :user, :tracks_data

  def find_existing_track(track_data)
    user.tracks.find_by(
      start_at: track_data['start_at'],
      end_at: track_data['end_at'],
      distance: track_data['distance']
    )
  end

  def create_track_record(track_data)
    attributes = track_data.except('segments', 'created_at', 'updated_at')
    attributes['created_at'] = track_data['created_at']
    attributes['updated_at'] = track_data['updated_at']

    user.tracks.create!(attributes)
  end

  def create_segments(track, segments_data)
    return unless segments_data.is_a?(Array)

    segments_data.each do |segment_data|
      next unless segment_data.is_a?(Hash)

      track.track_segments.create!(segment_data)
    end
  end
end
