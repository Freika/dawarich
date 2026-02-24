# frozen_string_literal: true

class Users::ExportData::Visits
  # @param user [User] the user whose visits to export
  # @param output_directory [Pathname, nil] directory where monthly files will be written (e.g., tmp/export/visits)
  #   If nil, returns array of visit hashes (legacy mode)
  def initialize(user, output_directory = nil)
    @user = user
    @output_directory = output_directory
    @monthly_writers = {}
    @monthly_file_paths = []
  end

  # Exports visits to monthly JSONL files grouped by started_at
  # @return [Array<String>] relative paths to the created monthly files (e.g., ["visits/2024/2024-01.jsonl"])
  #   In legacy mode (no output_directory), returns array of visit hashes
  def call
    if @output_directory
      stream_to_monthly_files
      @monthly_file_paths.sort
    else
      # Legacy mode: return array of hashes
      export_as_array
    end
  end

  private

  attr_reader :user, :output_directory

  def stream_to_monthly_files
    count = 0

    user.visits.includes(:place).find_each do |visit|
      visit_hash = build_visit_hash(visit)
      month_key = extract_month_key(visit)

      writer = monthly_writer_for(month_key)
      writer.puts(visit_hash.to_json)
      count += 1
    end

    Rails.logger.info "Exported #{count} visits to #{@monthly_file_paths.size} monthly files"
  ensure
    close_all_writers
  end

  def export_as_array
    user.visits.includes(:place).map do |visit|
      build_visit_hash(visit)
    end
  end

  def build_visit_hash(visit)
    visit_hash = visit.as_json(except: %w[user_id place_id id])

    visit_hash['place_reference'] = if visit.place
                                      {
                                        'name' => visit.place.name,
                                        'latitude' => visit.place.lat.to_s,
                                        'longitude' => visit.place.lon.to_s,
                                        'source' => visit.place.source
                                      }
                                    end

    visit_hash
  end

  def extract_month_key(visit)
    return 'unknown' if visit.started_at.blank?

    visit.started_at.utc.strftime('%Y-%m')
  rescue StandardError => e
    Rails.logger.warn "Failed to extract month from visit started_at: #{e.message}"
    'unknown'
  end

  def monthly_writer_for(month_key)
    @monthly_writers[month_key] ||= begin
      year = month_key == 'unknown' ? 'unknown' : month_key.split('-').first
      year_dir = output_directory.join(year)
      FileUtils.mkdir_p(year_dir)

      file_path = year_dir.join("#{month_key}.jsonl")
      relative_path = "visits/#{year}/#{month_key}.jsonl"
      @monthly_file_paths << relative_path

      File.open(file_path, 'w')
    end
  end

  def close_all_writers
    @monthly_writers.each_value(&:close)
    @monthly_writers.clear
  end
end
