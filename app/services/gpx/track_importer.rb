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
    handler = each_trkpt do |point_hash, tracker_id|
      data = prepare_point(point_hash, tracker_id)
      next unless data

      batch << data
      next if batch.size < BATCH_SIZE

      flush(batch)
      batch = []
    end
    flush(batch) unless batch.empty?
    record_element_counts(handler)
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
      handler.raise_if_fatal_error!
      handler
    end
  end

  def record_element_counts(handler)
    counts = {
      'waypoints_seen' => handler.waypoint_count,
      'trackpoints_seen' => handler.trackpoint_count,
      'route_points_seen' => handler.route_point_count,
      'parse_errors_seen' => handler.errors.size
    }.select { |_, value| value.positive? }
    return if counts.empty?

    if handler.errors.any?
      Rails.logger.warn(
        "GPX import #{import.id} recovered from #{handler.errors.size} XML error(s): #{handler.errors.first}"
      )
    end

    import.update!(raw_data: (import.raw_data || {}).merge(counts))
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

    attrs = {
      lonlat: "POINT(#{point['lon'].to_d} #{point['lat'].to_d})",
      altitude: elevation,
      timestamp: Time.zone.parse(point['time']).utc.to_i,
      tracker_id: tracker_id,
      import_id: import.id,
      velocity: speed(point),
      user_id: user_id,
      created_at: Time.current,
      updated_at: Time.current
    }
    attrs[:altitude_decimal] = elevation if Point.altitude_decimal_supported?
    attrs
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
    # libxml2 stops parsing at any well-formedness error, so a document whose
    # root element never closed lost data and is unusable whatever the message
    # says. Once the root did close, only these messages still mean the
    # document was unusable; anything else (e.g. an undeclared namespace
    # prefix on an extension element) was recovered from.
    FATAL_ERROR_PATTERNS = [
      /Premature end of data/i,
      /Extra content at the end/i,
      /Start tag expected/i
    ].freeze

    attr_reader :waypoint_count, :trackpoint_count, :route_point_count, :errors

    def initialize(import_id, import_name, &block)
      super()
      @import_id = import_id
      @import_name = import_name
      @callback = block
      @waypoint_count = 0
      @trackpoint_count = 0
      @route_point_count = 0
      @stack = nil
      @text = +''
      @trk_index = -1
      @seg_index = -1
      @trk_identity = nil
      @trk_identity_source = nil
      @capturing_trk_field = nil
      @capture_depth = 0
      @errors = []
      @depth = 0
      @root_closed = false
    end

    def start_element_namespace(name, attrs = [], _prefix = nil, _uri = nil, _namespaces = [])
      @depth += 1

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
      when 'wpt'
        @waypoint_count += 1
        return
      when 'rtept'
        @route_point_count += 1
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
        @trackpoint_count += 1
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
      # Nokogiri's SAX `error` callback fires for both fatal well-formedness
      # breaks and recoverable libxml2 errors (e.g. an undeclared namespace
      # prefix on an extension element), without surfacing the severity.
      # Collect every message and decide whether the document is unusable
      # after parsing completes -- raising here would abort an otherwise
      # valid import and discard every parsed <trkpt>.
      @errors << message
    end

    def raise_if_fatal_error!
      return if @errors.empty?

      fatal =
        if @root_closed
          @errors.find { |message| FATAL_ERROR_PATTERNS.any? { |pattern| pattern.match?(message) } }
        else
          @errors.last
        end
      return unless fatal

      raise Nokogiri::XML::SyntaxError, I18n.t('services.gpx.track_importer.parse_error', message: fatal)
    end

    def end_element_namespace(name, _prefix = nil, _uri = nil)
      @depth -= 1
      @root_closed = true if @depth.zero?

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
