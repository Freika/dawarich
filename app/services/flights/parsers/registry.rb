# frozen_string_literal: true

module Flights
  module Parsers
    class Registry
      PARSERS = [
        AirTrailJson
      ].freeze

      def self.parsers
        PARSERS
      end

      def self.formats
        PARSERS.map { |parser| { key: parser.key.to_s, label: parser.label } }
      end

      def self.accepted_extensions
        PARSERS.flat_map(&:extensions).uniq
      end

      def self.accept_attribute
        (accepted_extensions + %w[application/json text/json]).join(',')
      end

      def self.find(key)
        PARSERS.find { |parser| parser.key.to_s == key.to_s }
      end

      def self.find!(key)
        find(key) || raise(Error, "Unknown flight import format: #{key}")
      end

      # Parses file content into Flight attribute hashes.
      # format: nil/:auto for detection, or a parser key (e.g. :airtrail_json).
      def self.parse(content, format: nil)
        parser = resolve_parser(content, format)
        strict = format.present? && format.to_s != 'auto'
        data = parser.decode(content, strict: strict)
        raise Error, unsupported_message if data.nil? || !parser.detect?(data)

        parser.call(data)
      end

      def self.detect_and_parse(data, format: nil)
        parser = if format.present? && format.to_s != 'auto'
                   find!(format)
                 else
                   detect(data)
                 end
        raise Error, unsupported_message unless parser.detect?(data)

        parser.call(data)
      end

      def self.detect(data)
        PARSERS.find { |parser| parser.detect?(data) } ||
          raise(Error, unsupported_message)
      end

      def self.supported_format?(filename:, content_type: nil)
        ext = File.extname(filename.to_s).downcase
        return true if accepted_extensions.include?(ext)

        type = content_type.to_s
        type.in?(%w[application/json text/json application/octet-stream]) || type.end_with?('+json')
      end

      def self.resolve_parser(content, format)
        return find!(format) if format.present? && format.to_s != 'auto'

        PARSERS.each do |parser|
          data = parser.decode(content, strict: false)
          next if data.nil?
          return parser if parser.detect?(data)
        end

        raise Error, unsupported_message
      end
      private_class_method :resolve_parser

      def self.unsupported_message
        labels = PARSERS.map(&:label).join(', ')
        "Unsupported flight file format. Currently supported: #{labels}."
      end
      private_class_method :unsupported_message
    end
  end
end
