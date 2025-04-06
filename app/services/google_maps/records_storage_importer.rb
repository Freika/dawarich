# frozen_string_literal: true

# This class is used to import Google's Records.json file
# via the UI, vs the CLI, which uses the `GoogleMaps::RecordsImporter` class.

class GoogleMaps::RecordsStorageImporter
  BATCH_SIZE = 1000
  MAX_RETRIES = 3
  DOWNLOAD_TIMEOUT = 300 # 5 minutes timeout

  def initialize(import, user_id)
    @import = import
    @user = User.find_by(id: user_id)
  end

  def call
    process_file_in_batches
  rescue Oj::ParseError => e
    Rails.logger.error("JSON parsing error: #{e.message}")
    raise
  end

  private

  attr_reader :import, :user

  def process_file_in_batches
    file = download_file
    verify_file_integrity(file)
    locations = parse_file(file)
    process_locations_in_batches(locations) if locations.present?
  end

  def download_file
    retries = 0

    begin
      Timeout.timeout(DOWNLOAD_TIMEOUT) do
        import.file.download
      end
    rescue Timeout::Error => e
      retries += 1
      if retries <= MAX_RETRIES
        Rails.logger.warn("Download timeout, attempt #{retries} of #{MAX_RETRIES}")
        retry
      else
        Rails.logger.error("Download failed after #{MAX_RETRIES} attempts")
        raise
      end
    rescue StandardError => e
      Rails.logger.error("Download error: #{e.message}")
      raise
    end
  end

  def verify_file_integrity(file)
    # Verify file size
    expected_size = import.file.blob.byte_size
    actual_size = file.size

    if expected_size != actual_size
      raise "Incomplete download: expected #{expected_size} bytes, got #{actual_size} bytes"
    end

    # Verify checksum
    expected_checksum = import.file.blob.checksum
    actual_checksum = Base64.strict_encode64(Digest::MD5.digest(file))

    return unless expected_checksum != actual_checksum

    raise "Checksum mismatch: expected #{expected_checksum}, got #{actual_checksum}"
  end

  def parse_file(file)
    parsed_file = Oj.load(file, mode: :compat)
    return nil unless parsed_file.is_a?(Hash) && parsed_file['locations']

    parsed_file['locations']
  end

  def process_locations_in_batches(locations)
    batch = []
    index = 0

    locations.each do |location|
      batch << location

      next unless batch.size >= BATCH_SIZE

      process_batch(batch, index)
      index += BATCH_SIZE
      batch = []
    end

    # Process any remaining records that didn't make a full batch
    process_batch(batch, index) unless batch.empty?
  end

  def process_batch(batch, index)
    GoogleMaps::RecordsImporter.new(import, index).call(batch)
  end
end
