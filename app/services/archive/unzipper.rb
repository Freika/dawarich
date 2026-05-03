# frozen_string_literal: true

require 'zip'

module Archive
  class Unzipper
    class ArchiveTooLarge < StandardError; end

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
      rescue ::Zip::Error
        return Result.new(kind: :not_a_zip)
      rescue StandardError => e
        # Unexpected non-zip error (disk, NFS, permissions). Fall through to
        # the raw-file path rather than crashing the import, but log so the
        # underlying issue is visible in Sentry/Rails logs.
        Rails.logger.warn("Archive::Unzipper.inspect_archive failed on #{path}: #{e.class} #{e.message}")
        return Result.new(kind: :not_a_zip)
      end

      return Result.new(kind: :not_a_zip) if entries.nil?

      # Single-entry-with-unsupported-extension collapses to :multi_entry so
      # the existing Imports::ZipExtractor handles the filtering rather than
      # duplicating the supported-extensions list in two places.
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
        # Tempfile.create (not .new) returns a plain File without an
        # ObjectSpace finalizer, so the path survives GC of the File object.
        # The caller (Imports::Create) is responsible for unlinking.
        inner = Tempfile.create(['unzipped', ext], binmode: true)

        begin
          bytes_written = 0
          entry.get_input_stream do |stream|
            while (chunk = stream.read(64 * 1024))
              bytes_written += chunk.bytesize
              if bytes_written > MAX_EXTRACTED_SIZE
                inner.close
                File.unlink(inner.path) if File.exist?(inner.path)
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
          inner.close unless inner.closed?
          File.unlink(inner.path) if File.exist?(inner.path)
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
      Imports::ZipExtractor::SUPPORTED_EXTENSIONS.include?(File.extname(name).downcase)
    end
  end
end
