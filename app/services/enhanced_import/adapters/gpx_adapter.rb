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
        CAPTURED_FIELDS = %w[name type color].freeze

        def initialize(&block)
          super()
          @callback = block
          @attrs = nil
          @fields = {}
          @field = nil
          @text = +''
        end

        def start_element_namespace(name, attrs = [], _prefix = nil, _uri = nil, _namespaces = [])
          if name == 'wpt'
            @attrs = attrs.each_with_object({}) { |a, h| h[a.localname] = a.value }
            @fields = {}
            @field = nil
            return
          end

          return if @attrs.nil?
          return unless CAPTURED_FIELDS.include?(name)

          @field = name
          @text = +''
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
            return
          end

          return unless @field == name

          @fields[name] = @text.strip
          @field = nil
          @text = +''
        end

        private

        def emit
          return if @attrs.nil?

          latitude = @attrs['lat']
          longitude = @attrs['lon']
          return if latitude.blank? || longitude.blank?

          category = @fields['type'].presence

          @callback.call(
            Extracted::Place.new(
              external_place_id: identity(@fields['name'], latitude, longitude),
              name: @fields['name'].presence,
              latitude: latitude.to_f,
              longitude: longitude.to_f,
              semantic_type: category,
              geodata_extras: {},
              tag_name: category,
              tag_color: normalized_color(@fields['color'])
            )
          )
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
          when 6 then "##{hex}"
          when 8 then "##{hex[2, 6]}"
          end
        end
      end
    end
  end
end
