# frozen_string_literal: true

class Users::ExportData::Stats
  # @param user [User] the user whose stats to export
  # @param output_directory [Pathname, nil] directory where monthly files will be written (e.g., tmp/export/stats)
  #   If nil, returns array of stat hashes (legacy mode)
  def initialize(user, output_directory = nil)
    @user = user
    @output_directory = output_directory
    @monthly_writers = {}
    @monthly_file_paths = []
  end

  # Exports stats to monthly JSONL files grouped by their year/month fields
  # @return [Array<String>] relative paths to the created monthly files (e.g., ["stats/2024/2024-01.jsonl"])
  #   In legacy mode (no output_directory), returns array of stat hashes
  def call
    if @output_directory
      stream_to_monthly_files
      @monthly_file_paths.sort
    else
      # Legacy mode: return array of hashes
      user.stats.as_json(except: %w[user_id id])
    end
  end

  private

  attr_reader :user, :output_directory

  def stream_to_monthly_files
    count = 0

    user.stats.find_each do |stat|
      stat_hash = stat.as_json(except: %w[user_id id])
      month_key = extract_month_key(stat)

      writer = monthly_writer_for(month_key)
      writer.puts(stat_hash.to_json)
      count += 1
    end

    Rails.logger.info "Exported #{count} stats to #{@monthly_file_paths.size} monthly files"
  ensure
    close_all_writers
  end

  def extract_month_key(stat)
    return 'unknown' if stat.year.blank? || stat.month.blank?

    format('%<year>04d-%<month>02d', year: stat.year, month: stat.month)
  rescue StandardError => e
    Rails.logger.warn "Failed to extract month from stat year/month: #{e.message}"
    'unknown'
  end

  def monthly_writer_for(month_key)
    @monthly_writers[month_key] ||= begin
      year = month_key == 'unknown' ? 'unknown' : month_key.split('-').first
      year_dir = output_directory.join(year)
      FileUtils.mkdir_p(year_dir)

      file_path = year_dir.join("#{month_key}.jsonl")
      relative_path = "stats/#{year}/#{month_key}.jsonl"
      @monthly_file_paths << relative_path

      File.open(file_path, 'w')
    end
  end

  def close_all_writers
    @monthly_writers.each_value(&:close)
    @monthly_writers.clear
  end
end
