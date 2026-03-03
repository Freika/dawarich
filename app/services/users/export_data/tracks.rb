# frozen_string_literal: true

class Users::ExportData::Tracks
  # @param user [User] the user whose tracks to export
  # @param output_directory [Pathname, nil] directory where monthly files will be written (e.g., tmp/export/tracks)
  #   If nil, returns array of track hashes (legacy mode)
  def initialize(user, output_directory = nil)
    @user = user
    @output_directory = output_directory
    @monthly_writers = {}
    @monthly_file_paths = []
  end

  # Exports tracks to monthly JSONL files grouped by start_at
  # @return [Array<String>] relative paths to the created monthly files (e.g., ["tracks/2024/2024-01.jsonl"])
  #   In legacy mode (no output_directory), returns array of track hashes
  def call
    if @output_directory
      stream_to_monthly_files
      @monthly_file_paths.sort
    else
      user.tracks.includes(:track_segments).map { |track| build_track_hash(track) }
    end
  end

  private

  attr_reader :user, :output_directory

  def stream_to_monthly_files
    count = 0

    user.tracks.includes(:track_segments).find_each do |track|
      track_hash = build_track_hash(track)
      month_key = extract_month_key(track)

      writer = monthly_writer_for(month_key)
      writer.puts(track_hash.to_json)
      count += 1
    end

    Rails.logger.info "Exported #{count} tracks to #{@monthly_file_paths.size} monthly files"
  ensure
    close_all_writers
  end

  def build_track_hash(track)
    track_hash = track.as_json(except: %w[user_id id])

    # Serialize original_path as WKT string
    track_hash['original_path'] = track.original_path&.as_text

    # Serialize dominant_mode as integer to preserve enum value
    track_hash['dominant_mode'] = track.dominant_mode_before_type_cast

    # Embed track segments
    track_hash['segments'] = track.track_segments.map do |segment|
      segment.as_json(except: %w[track_id id])
    end

    track_hash
  end

  def extract_month_key(track)
    return 'unknown' if track.start_at.blank?

    track.start_at.utc.strftime('%Y-%m')
  rescue StandardError => e
    Rails.logger.warn "Failed to extract month from track start_at: #{e.message}"
    'unknown'
  end

  def monthly_writer_for(month_key)
    @monthly_writers[month_key] ||= begin
      year = month_key == 'unknown' ? 'unknown' : month_key.split('-').first
      year_dir = output_directory.join(year)
      FileUtils.mkdir_p(year_dir)

      file_path = year_dir.join("#{month_key}.jsonl")
      relative_path = "tracks/#{year}/#{month_key}.jsonl"
      @monthly_file_paths << relative_path

      File.open(file_path, 'w')
    end
  end

  def close_all_writers
    @monthly_writers.each_value(&:close)
    @monthly_writers.clear
  end
end
