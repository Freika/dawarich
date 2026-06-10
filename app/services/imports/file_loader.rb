# frozen_string_literal: true

module Imports
  module FileLoader
    extend ActiveSupport::Concern

    private

    def load_json_data
      Oj.load(load_file_content, mode: :compat)
    end

    # Exports written by some clients (notably Windows) can contain stray
    # non-UTF-8 bytes; Oj parses them without complaint, so downstream string
    # operations would raise ArgumentError. Replace invalid bytes upfront.
    def scrub_to_utf8(content)
      content.force_encoding(Encoding::UTF_8).scrub
    end

    def load_file_content
      content =
        if file_path && File.exist?(file_path)
          File.read(file_path)
        else
          Imports::SecureFileDownloader.new(import.file).download_with_verification
        end

      scrub_to_utf8(content)
    end

    # Returns a local file path, downloading from storage if needed.
    # Sets @temp_file_path for cleanup_temp_file to delete later.
    def resolve_file_path
      return file_path if file_path && File.exist?(file_path)

      @temp_file_path = Imports::SecureFileDownloader.new(import.file).download_to_temp_file
    end

    def cleanup_temp_file
      return unless @temp_file_path

      File.delete(@temp_file_path) if File.exist?(@temp_file_path)
    rescue StandardError => e
      Rails.logger.warn("Failed to cleanup temp file: #{e.message}")
    end
  end
end
