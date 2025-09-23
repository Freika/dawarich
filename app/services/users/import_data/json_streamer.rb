# frozen_string_literal: true

require 'yajl'

class Users::ImportData::JsonStreamer
  def initialize(zip_entry)
    @zip_entry = zip_entry
    @memory_tracker = Users::ImportData::MemoryTracker.new
  end

  def stream_parse
    Rails.logger.info "Starting JSON streaming for #{@zip_entry.name} (#{@zip_entry.size} bytes)"

    @memory_tracker.log("before_streaming")

    data = {}

    @zip_entry.get_input_stream do |input_stream|
      parser = Yajl::Parser.new(symbolize_keys: false)

      # Set up the parser to handle objects
      parser.on_parse_complete = proc do |parsed_data|
        Rails.logger.info "JSON streaming completed, parsed #{parsed_data.keys.size} entity types"

        # Process each entity type
        parsed_data.each do |entity_type, entity_data|
          if entity_data.is_a?(Array)
            Rails.logger.info "Streamed #{entity_type}: #{entity_data.size} items"
          end
        end

        data = parsed_data
        @memory_tracker.log("after_parsing")
      end

      # Stream parse the JSON
      begin
        parser.parse(input_stream)
      rescue Yajl::ParseError => e
        raise StandardError, "Invalid JSON format in data file: #{e.message}"
      end
    end

    @memory_tracker.log("streaming_completed")

    data
  rescue StandardError => e
    Rails.logger.error "JSON streaming failed: #{e.message}"
    raise e
  end

  private

  attr_reader :zip_entry
end