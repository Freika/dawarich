# frozen_string_literal: true

module Flights
  class ImportFromJson
    def initialize(user, json_string)
      @user = user
      @json_string = json_string
    end

    def call
      data = parse_json(@json_string)
      flights = Parsers::Registry.detect_and_parse(data)
      counts = Upsert.new(@user, flights, mode: :merge).call
      record_imported_at
      counts
    end

    private

    def parse_json(json_string)
      JSON.parse(json_string)
    rescue JSON::ParserError => e
      raise Parsers::Error, "Invalid JSON: #{e.message}"
    end

    def record_imported_at
      User.where(id: @user.id).update_all(
        ["settings = jsonb_set(settings, '{airtrail_last_imported_at}', to_jsonb(?::text)), updated_at = ?",
         Time.current.iso8601, Time.current]
      )
    end
  end
end
