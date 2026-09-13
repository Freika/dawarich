# frozen_string_literal: true

require 'zip'

module Imports
  class ZipExtractor
    SUPPORTED_EXTENSIONS = %w[.gpx .json .geojson .kml .kmz .csv .tcx .fit .rec].freeze
    MAX_FILES = 25_000

    GOOGLE_TAKEOUT_PATTERNS = {
      %r{Semantic Location History/\d{4}/\d{4}_\w+\.json}i => 'google_semantic_history',
      %r{Location History.*/Records\.json}i => 'google_records',
      /\ATimeline\.json\z/i => 'google_phone_takeout',
      %r{Location History.*/Timeline\.json}i => 'google_phone_takeout'
    }.freeze

    def initialize(import, user_id, file_path)
      @import = import
      @user_id = user_id
      @file_path = file_path
      @archive_name = @import.name || File.basename(file_path)
      @max_size = ENV.fetch('ZIP_MAX_EXTRACTED_SIZE', 2.gigabytes).to_i
    end

    def call
      temp_dir = Rails.root.join("tmp/imports/zip_extract_#{SecureRandom.hex(8)}").to_s

      begin
        # Copy the zip to a stable path so rubyzip can re-open it for compressed entries.
        # The original may be a Tempfile whose underlying file gets deleted by GC.
        @stable_zip_path = File.join(temp_dir, "_source#{File.extname(@file_path)}")
        FileUtils.mkdir_p(temp_dir)
        FileUtils.cp(@file_path, @stable_zip_path)

        extract_files(temp_dir)
        entries = collect_supported_files(temp_dir)
        known_entries = detect_google_takeout(entries) + detect_google_photos(entries)

        if known_entries.any?
          create_imports_from_entries(known_entries)
        else
          create_imports_from_entries(entries)
        end

        @import.destroy!
      rescue StandardError => e
        @import.update(status: :failed, error_message: e.message) unless @import.destroyed?
        raise
      ensure
        FileUtils.rm_rf(temp_dir) if temp_dir
      end
    end

    private

    def extract_files(temp_dir)
      total_size = 0

      ::Zip::File.open(@stable_zip_path) do |zip_file|
        entries = zip_file.select { |entry| extractable_entry?(entry) }
        raise "Too many files in archive (max #{MAX_FILES})" if entries.size > MAX_FILES

        entries.each do |entry|
          dest = File.join(temp_dir, entry.name)
          next unless File.expand_path(dest).start_with?("#{File.expand_path(temp_dir)}/")

          FileUtils.mkdir_p(File.dirname(dest))
          total_size += extract_entry(entry, dest)
          raise "Archive too large (max #{@max_size} bytes)" if total_size > @max_size
        end
      end
    end

    def extractable_entry?(entry)
      !entry.directory? && !entry.name.include?('..') && !entry.name.start_with?('/')
    end

    def extract_entry(entry, dest)
      bytes_written = 0
      File.open(dest, 'wb') do |out|
        entry.get_input_stream do |stream|
          while (chunk = stream.read(8192))
            bytes_written += chunk.bytesize
            out.write(chunk)
          end
        end
      end
      bytes_written
    end

    def collect_supported_files(temp_dir)
      Dir.glob(File.join(temp_dir, '**', '*'))
         .select { |f| File.file?(f) }
         .select { |f| SUPPORTED_EXTENSIONS.include?(File.extname(f).downcase) }
         .reject { |f| File.extname(f).downcase == '.zip' }
         .map { |f| { path: f, relative: f.sub("#{temp_dir}/", ''), source: nil } }
    end

    def detect_google_takeout(entries)
      matched = entries.select do |entry|
        GOOGLE_TAKEOUT_PATTERNS.each do |pattern, source|
          if entry[:relative].match?(pattern)
            entry[:source] = source
            break
          end
        end
        entry[:source].present?
      end

      matched.any? ? matched : []
    end

    def detect_google_photos(entries)
      entries.select do |entry|
        entry[:source].nil? &&
          json_entry?(entry) &&
          Imports::SourceDetector.new_from_file_header(entry[:path]).detect_source == :google_photos &&
          (entry[:source] = 'google_photos')
      end
    end

    def json_entry?(entry)
      File.extname(entry[:path]).downcase == '.json'
    end

    def create_imports_from_entries(entries)
      user = User.find(@user_id)
      seen_names = user.imports.where(name: entries.map { |entry| import_name_for(entry) }).pluck(:name).to_set

      new_imports = entries.filter_map do |entry|
        name = import_name_for(entry)
        next if seen_names.include?(name)

        seen_names << name
        build_import(user, entry, name)
      end

      enqueue_processing(new_imports)
    end

    def import_name_for(entry)
      "#{File.basename(entry[:path])} (from #{@archive_name})"
    end

    def build_import(user, entry, name)
      filename = File.basename(entry[:path])
      new_import = user.imports.build(name: name, source: entry[:source], skip_background_processing: true)
      new_import.file.attach(
        io: File.open(entry[:path]),
        filename: filename,
        content_type: Marcel::MimeType.for(name: filename)
      )
      new_import.save!
      new_import
    end

    def enqueue_processing(imports)
      return if imports.empty?

      ActiveJob.perform_all_later(imports.map { |import| Import::ProcessJob.new(import.id) })
    end
  end
end
