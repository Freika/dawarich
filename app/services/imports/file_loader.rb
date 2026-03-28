# frozen_string_literal: true

module Imports
  module FileLoader
    extend ActiveSupport::Concern

    private

    def load_json_data
      if file_path && File.exist?(file_path)
        Oj.load_file(file_path, mode: :compat)
      else
        file_content = Imports::SecureFileDownloader.new(import.file).download_with_verification
        Oj.load(file_content, mode: :compat)
      end
    end

    def load_file_content
      if file_path && File.exist?(file_path)
        File.read(file_path)
      else
        Imports::SecureFileDownloader.new(import.file).download_with_verification
      end
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
