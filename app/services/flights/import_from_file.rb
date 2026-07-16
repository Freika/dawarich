# frozen_string_literal: true

module Flights
  class ImportFromFile
    def initialize(user, content, format: nil)
      @user = user
      @content = content
      @format = format
    end

    def call
      flights = Parsers::Registry.parse(@content, format: @format)
      counts = Upsert.new(@user, flights, mode: :merge).call
      record_imported_at
      counts
    end

    private

    def record_imported_at
      User.where(id: @user.id).update_all(
        ["settings = jsonb_set(COALESCE(settings, '{}'::jsonb), '{flights_last_imported_at}', to_jsonb(?::text)), updated_at = ?",
         Time.current.iso8601, Time.current]
      )
    end
  end
end
