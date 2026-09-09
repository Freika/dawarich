# frozen_string_literal: true

module EnhancedImport
  module Adapters
    class BaseAdapter
      include Imports::FileLoader

      attr_reader :import, :file_path

      def initialize(import, file_path = nil)
        @import = import
        @file_path = file_path
      end

      def translate(&)
        raise NotImplementedError
      end

      protected

      # Large exports must never be read into memory whole; hand the caller an
      # IO over a local copy and clean the copy up afterwards. A single-entry
      # archive stays attached as the zip, so unwrap it before parsing.
      def stream_file(&block)
        path = unwrapped_path(resolve_file_path)
        File.open(path, 'rb', &block)
      ensure
        File.delete(@unwrapped_path) if @unwrapped_path && File.exist?(@unwrapped_path)
        cleanup_temp_file
      end

      # Same unwrapping for the adapters that parse the document whole.
      #
      # Scrubbed in place: scrub_to_utf8 returns a second full copy of the file,
      # so a large export was held twice over before Oj even started building
      # the object graph. scrub! rewrites the buffer we already have, and does
      # nothing at all when the bytes are already valid UTF-8 — the usual case.
      def load_json_data
        stream_file do |io|
          raw = io.read
          raw.force_encoding(Encoding::UTF_8)
          raw.scrub!
          Oj.load(raw, mode: :compat)
        end
      end

      def unwrapped_path(path)
        return path unless zip?(path)

        @unwrapped_path = Archive::Unzipper.extract_single(path)
      end

      def zip?(path)
        File.open(path, 'rb') { |io| io.read(4) } == "PK\x03\x04".b
      rescue StandardError
        false
      end

      def parse_lat_lng(latlng_string)
        return nil if latlng_string.blank?

        cleaned = latlng_string.to_s.gsub('°', '').gsub('°', '').strip
        parts = cleaned.split(/,\s*/)
        return nil if parts.size < 2

        [parts[0].to_f, parts[1].to_f]
      end

      def parse_e7(value)
        return nil if value.nil?

        value.to_f / 10**7
      end
    end
  end
end
