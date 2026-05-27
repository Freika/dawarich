# frozen_string_literal: true

class Geojson::Importer
  include Imports::Broadcaster
  include Imports::BulkInsertable
  include Imports::FileLoader
  include PointValidation

  BATCH_SIZE = 1000
  attr_reader :import, :user_id, :file_path

  def initialize(import, user_id, file_path = nil)
    @import  = import
    @user_id = user_id
    @file_path = file_path
  end

  def call
    path = resolve_file_path
    validate_json(path)
    initialize_stream
    ActiveRecord::Base.transaction do
      stream_features(path)
      flush_batch
      flush_places
    end

    raise Imports::NoImportableDataError if nothing_importable?
  ensure
    cleanup_temp_file
  end

  private

  def validate_json(path)
    parser = Oj::Parser.new(:validate)
    File.open(path, 'rb') { |io| parser.load(io) }
  rescue EncodingError, JSON::ParserError
    @legacy_parser_required = true
    File.open(path, 'rb') { |io| Oj.saj_parse(nil, io) }
  end

  def initialize_stream
    @points_batch = []
    @places_batch = []
    @processed_points = 0
    @processed_places = 0
  end

  def stream_features(path)
    handler = Geojson::StreamHandler.new { |feature| process_feature(feature) }

    File.open(path, 'rb') do |io|
      if @legacy_parser_required
        Oj.saj_parse(handler, io)
      else
        Oj::Parser.new(:saj, handler:).load(io)
      end
    end
  end

  def process_feature(feature)
    Geojson::Params.new(feature).each_entry do |kind, payload|
      case kind
      when :point then buffer_point(payload)
      when :place then buffer_place(payload)
      end
    end
  end

  def buffer_point(point)
    return if point[:lonlat].nil?

    @points_batch << point.merge(point_metadata)
    flush_batch if @points_batch.size >= BATCH_SIZE
  end

  def buffer_place(feature)
    @places_batch << feature
    flush_places if @places_batch.size >= BATCH_SIZE
  end

  def point_metadata
    {
      user_id: user_id,
      import_id: import.id,
      created_at: Time.current,
      updated_at: Time.current
    }
  end

  def flush_batch
    return if @points_batch.empty?

    batch = @points_batch
    @points_batch = []
    bulk_insert_points(batch)
    @processed_points += batch.size
    broadcast_import_progress(import, @processed_points)
  end

  def flush_places
    return if @places_batch.empty?

    batch = @places_batch
    @places_batch = []
    @processed_places += Places::GeojsonPointImporter.new(import, user_id, batch).call
  end

  # Counts rows the file actually accounted for — inserted or already present —
  # rather than features offered, so a feature whose coordinates turn out to be
  # unusable cannot pass for a successful import. A file that yields nothing at
  # all is reported the way the GPX importer reports it, not completed silently.
  def nothing_importable?
    @processed_points.zero? && @processed_places.zero?
  end

  def atomic_bulk_insert?
    true
  end

  def importer_name
    'GeoJSON'
  end
end
