# frozen_string_literal: true

module EnhancedImport
  class DestroyJob < ApplicationJob
    queue_as :extractions

    def perform(import_id, expected: nil)
      import = Import.find_by(id: import_id)
      return if import.nil?
      return if expected && !Imports::ExtractionCommands.matches?(import, expected)
      return if EnhancedImport::Commands.forward_destroy(import, event_id: job_id)

      Imports::ExtractionCommands.with_session(import, expected) do
        fence = ->(&block) { Imports::ExtractionCommands.effect!(import, expected, &block) }
        EnhancedImport::Destroy.new(import, **(expected ? { fence: } : {})).call
        EnhancedImport::CardBroadcaster.call(import)
      end
    rescue Imports::ExtractionCommands::Lost
      nil
    rescue StandardError => e
      # The controller parks the import in `running`; without this it would
      # spin forever with no way for the user to retry.
      if import
        begin
          Imports::ExtractionCommands.effect!(import, expected) do
            import.update_columns(
              additional_data_extraction_status: Import.additional_data_extraction_statuses[:failed],
              additional_data_extraction: (import.additional_data_extraction || {}).merge(
                'error_message' => "Removing extracted data failed: #{e.message}"
              )
            )
          end
        rescue Imports::ExtractionCommands::Lost
          nil
        end
      end
      EnhancedImport::CardBroadcaster.call(import) if import
      ExceptionReporter.call(e, 'Failed to remove extracted import data')
      raise
    end
  end
end
