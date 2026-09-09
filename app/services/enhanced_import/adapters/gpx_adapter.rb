# frozen_string_literal: true

require 'digest/sha1'
require 'nokogiri'

module EnhancedImport
  module Adapters
    class GpxAdapter < BaseAdapter
      XML_BOMS = [
        "\xEF\xBB\xBF".b,
        "\xFE\xFF".b,
        "\xFF\xFE".b,
        "\x00\x00\xFE\xFF".b,
        "\xFF\xFE\x00\x00".b
      ].freeze

      def translate(&block)
        return enum_for(:translate) unless block_given?
        return if import.gpx_without_waypoints?

        stream_file do |io|
          seek_to_document_start(io)
          Nokogiri::XML::SAX::Parser.new(WptStreamHandler.new(&block)).parse(io)
        end
      end

      private

      def seek_to_document_start(io)
        prefix = io.read(256) || ''
        offset = XML_BOMS.any? { |bom| prefix.start_with?(bom) } ? 0 : prefix.index('<') || 0
        io.seek(offset)
      end

      class WptStreamHandler < Nokogiri::XML::SAX::Document
        DIRECT_FIELDS = %w[name type].freeze
        NESTED_FIELDS = %w[color].freeze

        def initialize(&block)
          super()
          @callback = block
          @attrs = nil
          @fields = {}
          @field = nil
          @depth = 0
          @text = +''
        end

        def start_element_namespace(name, attrs = [], _prefix = nil, _uri = nil, _namespaces = [])
          if name == 'wpt'
            @attrs = attrs.each_with_object({}) { |a, h| h[a.localname] = a.value }
            @fields = {}
            @field = nil
            @depth = 0
            return
          end

          return if @attrs.nil?

          @depth += 1
          return if @field
          return unless capturable?(name)

          @field = name
          @text = +''
        end

        def capturable?(name)
          (DIRECT_FIELDS.include?(name) && @depth == 1) || NESTED_FIELDS.include?(name)
        end

        def characters(string)
          @text << string if @field
        end

        def end_element_namespace(name, _prefix = nil, _uri = nil)
          if name == 'wpt'
            emit
            @attrs = nil
            @fields = {}
            @field = nil
            @depth = 0
            return
          end

          return if @attrs.nil?

          if @field == name
            @fields[name] = @text.strip
            @field = nil
            @text = +''
          end

          @depth -= 1
        end

        private

        def emit
          return if @attrs.nil?

          latitude = coordinate(@attrs['lat'])
          longitude = coordinate(@attrs['lon'])
          return if latitude.nil? || longitude.nil?
          return if Points::NullIsland.coordinates?(longitude, latitude)

          category = @fields['type'].presence

          @callback.call(
            Extracted::Place.new(
              external_place_id: identity(@fields['name'], latitude, longitude),
              name: @fields['name'].presence,
              latitude: latitude,
              longitude: longitude,
              semantic_type: category,
              geodata_extras: {},
              tag_name: category,
              tag_color: normalized_color(@fields['color'])
            )
          )
        end

        def coordinate(value)
          return nil if value.blank?

          Float(value)
        rescue ArgumentError, TypeError
          nil
        end

        def identity(name, latitude, longitude)
          seed = format(
            '%<name>s|%<latitude>.5f|%<longitude>.5f',
            name: name.to_s.strip.downcase,
            latitude: latitude.to_f,
            longitude: longitude.to_f
          )

          "gpx:#{Digest::SHA1.hexdigest(seed)[0, 32]}"
        end

        def normalized_color(value)
          return if value.blank?

          hex = value.to_s.strip.delete_prefix('#').downcase
          return unless hex.match?(/\A[0-9a-f]+\z/)

          case hex.length
          when 3 then "##{hex.chars.map { |c| c * 2 }.join}"
          when 6 then "##{hex}"
          when 8 then "##{hex[2, 6]}"
          end
        end
      end
    end
  end
end
