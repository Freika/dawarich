# frozen_string_literal: true

module EnhancedImport
  class DestroyJob < ApplicationJob
    queue_as :extractions

    def perform(import_id)
      import = Import.find_by(id: import_id)
      return if import.nil?
      return if EnhancedImport::Commands.forward_destroy(import, event_id: job_id)

      EnhancedImport::Destroy.new(import).call
      EnhancedImport::CardBroadcaster.call(import)
    rescue StandardError => e
      # The controller parks the import in `running`; without this it would
      # spin forever with no way for the user to retry.
      import&.update_columns(
        additional_data_extraction_status: Import.additional_data_extraction_statuses[:failed],
        additional_data_extraction: (import.additional_data_extraction || {}).merge(
          'error_message' => "Removing extracted data failed: #{e.message}"
        )
      )
      EnhancedImport::CardBroadcaster.call(import) if import
      ExceptionReporter.call(e, 'Failed to remove extracted import data')
      raise
    end
  end
end
