# frozen_string_literal: true

# This class is used to import Google's Records.json file
# via the UI, vs the CLI, which uses the `GoogleMaps::RecordsImporter` class.

class GoogleMaps::RecordsStorageImporter
  BATCH_SIZE = 1000

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
    retries = 0
    max_retries = 3

    begin
      file = Timeout.timeout(300) do # 5 minutes timeout
        import.file.download
      end

      # Verify file size
      expected_size = import.file.blob.byte_size
      actual_size = file.size

      if expected_size != actual_size
        raise "Incomplete download: expected #{expected_size} bytes, got #{actual_size} bytes"
      end

      # Verify checksum
      expected_checksum = import.file.blob.checksum
      actual_checksum = Base64.strict_encode64(Digest::MD5.digest(file))

      if expected_checksum != actual_checksum
        raise "Checksum mismatch: expected #{expected_checksum}, got #{actual_checksum}"
      end

      parsed_file = Oj.load(file, mode: :compat)

      return unless parsed_file.is_a?(Hash) && parsed_file['locations']

      batch = []
      index = 0

      parsed_file['locations'].each do |location|
        batch << location

        next if batch.size < BATCH_SIZE

        index += BATCH_SIZE

        GoogleMaps::RecordsImporter.new(import, index).call(batch)

        batch = []
      end
    rescue Timeout::Error => e
      retries += 1
      if retries <= max_retries
        Rails.logger.warn("Download timeout, attempt #{retries} of #{max_retries}")
        retry
      else
        Rails.logger.error("Download failed after #{max_retries} attempts")
        raise
      end
    rescue StandardError => e
      Rails.logger.error("Download error: #{e.message}")
      raise
    end
  end
end
