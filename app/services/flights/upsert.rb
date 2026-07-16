# frozen_string_literal: true

module Flights
  class Upsert
    MODES = %i[merge replace].freeze

    # @param flight_attrs [Array<Hash>] Flight-ready attribute hashes (not raw provider payloads)
    def initialize(user, flight_attrs, mode: :merge)
      @user = user
      @flight_attrs = flight_attrs
      @mode = mode.to_sym
      raise ArgumentError, "Invalid mode: #{mode}" unless MODES.include?(@mode)
    end

    def call
      created = 0
      updated = 0
      seen = []

      Flight.transaction do
        @flight_attrs.each do |attrs|
          seen << attrs[:external_id]

          begin
            Flight.transaction(requires_new: true) do
              flight = @user.flights.find_or_initialize_by(external_id: attrs[:external_id])
              was_new = flight.new_record?
              flight.update!(attrs)
              was_new ? created += 1 : updated += 1
            end
          rescue ActiveRecord::RecordNotUnique
            updated += 1 if @user.flights.find_by(external_id: attrs[:external_id])&.update!(attrs)
          end
        end

        deleted = @mode == :replace ? @user.flights.where.not(external_id: seen).delete_all : 0
        { created: created, updated: updated, deleted: deleted }
      end
    end
  end
end
