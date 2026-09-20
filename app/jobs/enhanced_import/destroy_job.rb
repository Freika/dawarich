# frozen_string_literal: true

module EnhancedImport
  class DestroyJob < ApplicationJob
    queue_as :extractions

    def perform(import_id)
      import = Import.find_by(id: import_id)
      return if import.nil?

      EnhancedImport::Destroy.new(import).call
      broadcast_card(import)
    rescue StandardError => e
      # The controller parks the import in `running`; without this it would
      # spin forever with no way for the user to retry.
      import&.update_columns(
        additional_data_extraction_status: Import.additional_data_extraction_statuses[:failed],
        additional_data_extraction: (import.additional_data_extraction || {}).merge(
          'error_message' => "Removing extracted data failed: #{e.message}"
        )
      )
      broadcast_card(import) if import
      ExceptionReporter.call(e, 'Failed to remove extracted import data')
      raise
    end

    private

    def broadcast_card(import)
      Turbo::StreamsChannel.broadcast_replace_to(
        "import_#{import.id}_extraction",
        target: "import-#{import.id}-extraction",
        partial: 'imports/extraction_card',
        locals: { import: import.reload }
      )
    rescue StandardError => e
      Rails.logger.warn("[EnhancedImport::DestroyJob] card broadcast failed import_id=#{import.id}: #{e.message}")
    end
  end
end
