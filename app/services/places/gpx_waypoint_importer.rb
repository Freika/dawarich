# frozen_string_literal: true

require 'nokogiri'

class Places::GpxWaypointImporter
  include Places::BulkInsertable

  DEFAULT_NAME = 'Imported waypoint'

  attr_reader :import, :user_id, :file_path, :parsed_count, :imported_count

  def initialize(import, user_id, file_path)
    @import = import
    @user_id = user_id
    @file_path = file_path
    @parsed_count = 0
    @imported_count = 0
  end

  def call
    batch = []
    each_wpt do |wpt|
      row = prepare_place(wpt)
      next unless row

      @parsed_count += 1
      batch << row
      next if batch.size < BATCH_SIZE

      flush(batch)
      batch = []
    end
    flush(batch)
    @imported_count
  end

  private

  def each_wpt(&block)
    File.open(file_path, 'rb') do |io|
      Gpx::DocumentStart.seek(io)
      handler = WptStreamHandler.new(&block)
      Nokogiri::XML::SAX::Parser.new(handler).parse(io)
    end
  end

  def prepare_place(wpt)
    place_row(
      name: wpt['name'],
      latitude: wpt['lat'],
      longitude: wpt['lon'],
      source: Place.sources[:gpx_waypoint]
    )
  end

  def default_place_name
    DEFAULT_NAME
  end

  def flush(batch)
    @imported_count += insert_places(batch)
  end

  class WptStreamHandler < Nokogiri::XML::SAX::Document
    CAPTURED_CHILDREN = %w[name].freeze

    def initialize(&block)
      super()
      @callback = block
      @current = nil
      @capturing_child = nil
      @text = +''
    end

    def start_element_namespace(name, attrs = [], _prefix = nil, _uri = nil, _namespaces = [])
      if name == 'wpt'
        @current = attrs.each_with_object({}) { |a, h| h[a.localname] = a.value }
        @capturing_child = nil
        @text = +''
        return
      end

      return unless @current
      return unless CAPTURED_CHILDREN.include?(name)

      @capturing_child = name
      @text = +''
    end

    def characters(string)
      @text << string if @capturing_child
    end

    def end_element_namespace(name, _prefix = nil, _uri = nil)
      if name == 'wpt' && @current
        @callback.call(@current)
        @current = nil
        @capturing_child = nil
        @text = +''
        return
      end

      return unless @capturing_child && name == @capturing_child

      @current[@capturing_child] = @text.strip if @current
      @capturing_child = nil
      @text = +''
    end

    def error(message)
      raise Nokogiri::XML::SyntaxError, "GPX parse error: #{message}"
    end
  end
end
