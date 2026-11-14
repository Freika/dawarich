# frozen_string_literal: true

module Imports
  module FileLoader
    extend ActiveSupport::Concern

    # Whole-file importers (JSON via Oj, TCX via Hash.from_xml) read the entire
    # file into memory and build a full object graph. A small compressed upload
    # can expand to the 2 GiB disk cap and OOM-kill the worker, so the in-memory
    # size is bounded by an Instance setting an admin can raise for larger workers.

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
          enforce_parse_limit!(File.size(file_path))
          File.read(file_path)
        else
          Imports::SecureFileDownloader.new(import.file).download_with_verification
        end

      enforce_parse_limit!(content.bytesize)
      scrub_to_utf8(content)
    end

    # `setting` lets a parser with a different memory profile (KML, whose DOM
    # amplifies far more than Oj) apply its own, lower bound.
    def enforce_parse_limit!(bytes, setting = :import_max_file_size_mb)
      max_mb = InstanceSettings::Resolver.value(setting)
      return if bytes <= max_mb.megabytes

      raise Imports::FileTooLarge,
            "import file is #{bytes} bytes (max #{max_mb} MB); raise the limit in Settings → Instance → Imports"
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
