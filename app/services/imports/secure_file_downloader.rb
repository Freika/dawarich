# frozen_string_literal: true

class Imports::SecureFileDownloader
  DOWNLOAD_TIMEOUT = 300 # 5 minutes timeout
  MAX_RETRIES = 3

  def initialize(storage_attachment)
    @storage_attachment = storage_attachment
  end

  def download_with_verification
    file_content = download_to_string
    verify_file_integrity(file_content)
    file_content
  end

  def download_to_temp_file
    retries = 0
    temp_file = nil

    begin
      Timeout.timeout(DOWNLOAD_TIMEOUT) do
        temp_file = create_temp_file

        # Download directly to temp file
        storage_attachment.download do |chunk|
          temp_file.write(chunk)
        end
        temp_file.rewind

        # If file is empty, try alternative download method
        if temp_file.empty?
          Rails.logger.warn('No content received from block download, trying alternative method')
          temp_file.write(storage_attachment.blob.download)
          temp_file.rewind
        end
      end
    rescue Timeout::Error => e
      retries += 1
      if retries <= MAX_RETRIES
        Rails.logger.warn("Download timeout, attempt #{retries} of #{MAX_RETRIES}")
        cleanup_temp_file(temp_file)
        retry
      else
        Rails.logger.error("Download failed after #{MAX_RETRIES} attempts")
        cleanup_temp_file(temp_file)
        raise
      end
    rescue StandardError => e
      Rails.logger.error("Download error: #{e.message}")
      cleanup_temp_file(temp_file)
      raise
    end

    raise 'Download completed but no content was received' if temp_file.empty?

    verify_temp_file_integrity(temp_file)
    temp_file.path

    # Keep temp file open so it can be read by other processes
    # Caller is responsible for cleanup
  end

  private

  attr_reader :storage_attachment

  def download_to_string
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
        if file_content.blank?
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

    raise 'Download completed but no content was received' if file_content.blank?

    file_content
  end

  def create_temp_file
    extension = File.extname(storage_attachment.filename.to_s)
    basename = File.basename(storage_attachment.filename.to_s, extension)
    Tempfile.new(["#{basename}_#{Time.now.to_i}", extension], binmode: true)
  end

  def cleanup_temp_file(temp_file)
    return unless temp_file

    temp_file.close unless temp_file.closed?
    temp_file.unlink if File.exist?(temp_file.path)
  rescue StandardError => e
    Rails.logger.warn("Failed to cleanup temp file: #{e.message}")
  end

  def verify_file_integrity(file_content)
    return if file_content.blank?

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

  def verify_temp_file_integrity(temp_file)
    return if temp_file.blank?

    # Verify file size
    expected_size = storage_attachment.blob.byte_size
    actual_size = temp_file.size

    if expected_size != actual_size
      raise "Incomplete download: expected #{expected_size} bytes, got #{actual_size} bytes"
    end

    # Verify checksum
    expected_checksum = storage_attachment.blob.checksum
    temp_file.rewind
    actual_checksum = Base64.strict_encode64(Digest::MD5.digest(temp_file.read))
    temp_file.rewind

    return unless expected_checksum != actual_checksum

    raise "Checksum mismatch: expected #{expected_checksum}, got #{actual_checksum}"
  end
end
