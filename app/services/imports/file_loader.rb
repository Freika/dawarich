# frozen_string_literal: true

module Imports
  module FileLoader
    extend ActiveSupport::Concern

    # Whole-file importers (JSON via Oj, TCX via Hash.from_xml) read the entire
    # file into memory and build a full object graph. A small compressed upload
    # can expand to the 2 GiB disk cap and OOM-kill the worker, so bound the
    # in-memory size here. Configurable for operators with larger workers.
    # Measured: a 256 MiB JSON parses to ~690 MiB with Oj, so 512 MiB stays well
    # within a default 4 GiB worker.
    DEFAULT_MAX_PARSE_BYTES = 512.megabytes

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

    # `limit`/`env_var` let a parser with a different memory profile (KML, whose
    # DOM amplifies far more than Oj) pass its own, lower bound.
    def enforce_parse_limit!(bytes, limit = DEFAULT_MAX_PARSE_BYTES, env_var: 'IMPORT_MAX_PARSE_BYTES')
      max = ENV.fetch(env_var, limit).to_i
      return if bytes <= max

      raise Imports::FileTooLarge,
            "import file is #{bytes} bytes (max #{max}); raise #{env_var} to allow it"
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
