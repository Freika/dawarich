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
    end
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
    @processed_points = 0
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
    Geojson::Params.new(feature).each_point do |point|
      next if point[:lonlat].nil?

      @points_batch << point.merge(point_metadata)
      flush_batch if @points_batch.size >= BATCH_SIZE
    end
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

  def atomic_bulk_insert?
    true
  end

  def importer_name
    'GeoJSON'
  end
end
