# frozen_string_literal: true

module EnhancedImport
  class Destroy
    attr_reader :import

    def initialize(import)
      @import = import
    end

    BATCH_SIZE = 500

    def call
      place_ids = extracted_place_ids

      destroy_in_batches(owned(Visit))
      destroy_in_batches(owned(Track))
      destroy_orphaned_places(place_ids)

      reset_extraction_state

      true
    end

    private

    def owned(klass)
      klass.where(user_id: import.user_id, import_id: import.id)
    end

    def extracted_place_ids
      owned(Place).pluck(:id)
    end

    # Places outlive their extraction when Dawarich's own detection later
    # attached a visit to them; dropping those would strand a visit the user
    # never imported.
    def destroy_orphaned_places(place_ids)
      return if place_ids.empty?

      still_referenced = Visit.where(place_id: place_ids).distinct.pluck(:place_id)
      destroy_in_batches(Place.where(user_id: import.user_id, id: place_ids - still_referenced))
    end

    # One transaction per batch: a multi-thousand-visit undo must not hold a
    # single long write transaction on a production database.
    def destroy_in_batches(relation)
      relation.in_batches(of: BATCH_SIZE) do |batch|
        ActiveRecord::Base.transaction { batch.each(&:destroy) }
      end
    end

    def reset_extraction_state
      import.update_columns(
        additional_data_extraction_status: Import.additional_data_extraction_statuses[:not_attempted],
        additional_data_extraction: {}
      )
    end
  end
end
