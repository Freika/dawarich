# frozen_string_literal: true

require 'zip'

module Archive
  class Unzipper
    class ArchiveTooLarge < StandardError; end

    SUPPORTED_INNER_EXTENSIONS = %w[.gpx .json .geojson .kml .kmz .csv .tcx .fit .rec].freeze

    MAX_EXTRACTED_SIZE = ENV.fetch('ZIP_MAX_EXTRACTED_SIZE', 2.gigabytes).to_i
    ZIP_MAGIC = "PK\x03\x04".b.freeze

    Result = Struct.new(:kind, :entry_name, keyword_init: true)

    def self.inspect_archive(path)
      return Result.new(kind: :not_a_zip) unless zip_magic?(path)

      entries = nil
      begin
        ::Zip::File.open(path) do |zf|
          entries = zf.entries.reject(&:directory?)
        end
      rescue StandardError
        return Result.new(kind: :not_a_zip)
      end

      return Result.new(kind: :not_a_zip) if entries.nil?

      if entries.size == 1 && supported_extension?(entries.first.name)
        Result.new(kind: :single_entry, entry_name: entries.first.name)
      else
        Result.new(kind: :multi_entry)
      end
    end

    def self.extract_single(path)
      ::Zip::File.open(path) do |zf|
        entry = zf.entries.reject(&:directory?).first
        raise ArgumentError, 'zip has no entries' unless entry

        ext = File.extname(entry.name)
        inner = Tempfile.new(['unzipped', ext], binmode: true)

        begin
          bytes_written = 0
          entry.get_input_stream do |stream|
            while (chunk = stream.read(64 * 1024))
              bytes_written += chunk.bytesize
              if bytes_written > MAX_EXTRACTED_SIZE
                inner.close!
                raise ArchiveTooLarge, "entry exceeds #{MAX_EXTRACTED_SIZE} bytes"
              end

              inner.write(chunk)
            end
          end
          inner.close
          inner.path
        rescue ArchiveTooLarge
          raise
        rescue StandardError
          inner.close! if inner && !inner.closed?
          raise
        end
      end
    end

    def self.zip_magic?(path)
      File.open(path, 'rb') { |f| f.read(4) } == ZIP_MAGIC
    rescue StandardError
      false
    end

    def self.supported_extension?(name)
      SUPPORTED_INNER_EXTENSIONS.include?(File.extname(name).downcase)
    end
  end
end
