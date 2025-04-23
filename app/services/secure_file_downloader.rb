# frozen_string_literal: true

class SecureFileDownloader
  DOWNLOAD_TIMEOUT = 300 # 5 minutes timeout
  MAX_RETRIES = 3

  def initialize(storage_attachment)
    @storage_attachment = storage_attachment
  end

  def download_with_verification
    retries = 0
    file_content = nil

    begin
      Timeout.timeout(DOWNLOAD_TIMEOUT) do
        # Download the file to a string
        tempfile = Tempfile.new("download_#{Time.now.to_i}", binmode: true)
        begin
          # Try to download block-by-block
          storage_attachment.download do |chunk|
            tempfile.write(chunk)
          end
          tempfile.rewind
          file_content = tempfile.read
        ensure
          tempfile.close
          tempfile.unlink
        end

        # If we didn't get any content but no error occurred, try a different approach
        if file_content.nil? || file_content.empty?
          Rails.logger.warn('No content received from block download, trying alternative method')
          # Some ActiveStorage attachments may work differently, try direct access if possible
          file_content = storage_attachment.blob.download
        end
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

    raise 'Download completed but no content was received' if file_content.nil? || file_content.empty?

    verify_file_integrity(file_content)
    file_content
  end

  private

  attr_reader :storage_attachment

  def verify_file_integrity(file_content)
    return if file_content.nil? || file_content.empty?

    # Verify file size
    expected_size = storage_attachment.blob.byte_size
    actual_size = file_content.bytesize

    if expected_size != actual_size
      raise "Incomplete download: expected #{expected_size} bytes, got #{actual_size} bytes"
    end

    # Verify checksum
    expected_checksum = storage_attachment.blob.checksum
    actual_checksum = Base64.strict_encode64(Digest::MD5.digest(file_content))

    return unless expected_checksum != actual_checksum

    raise "Checksum mismatch: expected #{expected_checksum}, got #{actual_checksum}"
  end
end
