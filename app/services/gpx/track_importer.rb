# frozen_string_literal: true

require 'digest/sha1'
require 'nokogiri'

class Gpx::TrackImporter
  include Imports::Broadcaster
  include Imports::BulkInsertable
  include Imports::FileLoader

  BATCH_SIZE = 1000
  XML_BOMS = [
    "\xEF\xBB\xBF".b,
    "\xFE\xFF".b,
    "\xFF\xFE".b,
    "\x00\x00\xFE\xFF".b,
    "\xFF\xFE\x00\x00".b
  ].freeze

  attr_reader :import, :user_id, :file_path

  def initialize(import, user_id, file_path = nil)
    @import = import
    @user_id = user_id
    @file_path = file_path
  end

  def call
    batch = []
    each_trkpt do |point_hash, tracker_id|
      data = prepare_point(point_hash, tracker_id)
      next unless data

      batch << data
      next if batch.size < BATCH_SIZE

      flush(batch)
      batch = []
    end
    flush(batch) unless batch.empty?
  ensure
    cleanup_temp_file
  end

  private

  def each_trkpt(&block)
    path = resolve_file_path
    File.open(path, 'rb') do |io|
      seek_to_document_start(io)
      handler = TrkptStreamHandler.new(import.id, import.name, &block)
      Nokogiri::XML::SAX::Parser.new(handler).parse(io)
    end
  end

  def seek_to_document_start(io)
    prefix = io.read(256) || ''
    offset = XML_BOMS.any? { |bom| prefix.start_with?(bom) } ? 0 : prefix.index('<') || 0
    io.seek(offset)
  end

  def flush(batch)
    inserted = bulk_insert_points(batch)
    broadcast_import_progress(import, inserted)
  end

  def prepare_point(point, tracker_id)
    return if point['lat'].blank? || point['lon'].blank? || point['time'].blank?

    elevation = point['ele'].to_f

    {
      lonlat: "POINT(#{point['lon'].to_d} #{point['lat'].to_d})",
      altitude: elevation,
      altitude_decimal: elevation,
      timestamp: Time.zone.parse(point['time']).utc.to_i,
      tracker_id: tracker_id,
      import_id: import.id,
      velocity: speed(point),
      user_id: user_id,
      created_at: Time.current,
      updated_at: Time.current
    }
  end

  def importer_name
    'GPX'
  end

  def speed(point)
    return if point['extensions'].blank?

    value = point.dig('extensions', 'speed')
    extensions = point.dig('extensions', 'TrackPointExtension')
    value ||= extensions.is_a?(Hash) ? extensions['speed'] : nil

    value&.to_f&.round(1)
  end

  class TrkptStreamHandler < Nokogiri::XML::SAX::Document
    def initialize(import_id, import_name, &block)
      super()
      @import_id = import_id
      @import_name = import_name
      @callback = block
      @stack = nil
      @text = +''
      @trk_index = -1
      @seg_index = -1
      @trk_identity = nil
      @trk_identity_source = nil
      @capturing_trk_field = nil
      @capture_depth = 0
    end

    def start_element_namespace(name, attrs = [], _prefix = nil, _uri = nil, _namespaces = [])
      case name
      when 'trk'
        @trk_index += 1
        @seg_index = -1
        @trk_identity = nil
        @trk_identity_source = nil
        @capturing_trk_field = nil
        @capture_depth = 0
        return
      when 'trkseg'
        @seg_index += 1
        return
      end

      if @capturing_trk_field
        @capture_depth += 1
        return
      end

      if @stack.nil? && !@trk_index.negative? && @seg_index.negative? && %w[src name].include?(name)
        @capturing_trk_field = name
        @capture_depth = 0
        @text = +''
        return
      end

      attrs_h = attrs.each_with_object({}) { |a, h| h[a.localname] = a.value }
      if name == 'trkpt' && @stack.nil?
        @stack = [attrs_h]
        @text = +''
      elsif @stack
        @stack.last[name] = attrs_h
        @stack.push(attrs_h)
        @text = +''
      end
    end

    def characters(string)
      return if @capturing_trk_field && @capture_depth.positive?

      @text << string if @stack || @capturing_trk_field
    end

    def error(message)
      raise Nokogiri::XML::SyntaxError, "GPX parse error: #{message}"
    end

    def end_element_namespace(name, _prefix = nil, _uri = nil)
      if @capturing_trk_field
        if @capture_depth.positive?
          @capture_depth -= 1
          return
        end

        if name == @capturing_trk_field
          assign_trk_identity(@text.strip, @capturing_trk_field)
          @capturing_trk_field = nil
          @text = +''
          return
        end
      end

      return if %w[trk trkseg].include?(name)
      return unless @stack

      closed = @stack.pop
      if @stack.empty?
        @callback.call(closed, tracker_id)
        @stack = nil
      else
        @stack.last[name] = @text.strip if closed.empty?
        @text = +''
      end
    end

    private

    def assign_trk_identity(value, source)
      return if value.blank?
      return if source == 'name' && @trk_identity_source == 'src'

      @trk_identity = value
      @trk_identity_source = source
    end

    def tracker_id
      return "import-#{@import_id}-orphan" if @trk_index.negative?

      trk_key = stable_trk_key || "import-#{@import_id}-trk-#{@trk_index}"
      "#{trk_key}-seg-#{[@seg_index, 0].max}"
    end

    def stable_trk_key
      return nil if @trk_identity.blank?

      identity = @trk_identity_source == 'src' ? @trk_identity : "#{@trk_identity}|import:#{@import_name}"
      "gpx-#{Digest::SHA1.hexdigest(identity)[0, 16]}-trk-#{@trk_index}"
    end
  end
end
