# frozen_string_literal: true

module EnhancedImport
  module Commands
    EXTRACT = 'enhanced_import.extract_gpx'
    DESTROY = 'enhanced_import.destroy_gpx'

    module_function

    def forward_extract(import, attempt:, event_id:)
      return false unless import.gpx? && oban?(EXTRACT)

      forward(EXTRACT, { 'import_id' => import.id, 'lock_attempt' => attempt }, import, event_id,
              'EnhancedImport::ExtractJob')
    end

    def forward_destroy(import, event_id:)
      return false unless import.gpx? && oban?(DESTROY) && !owns_visits_or_tracks?(import)

      forward(DESTROY, { 'import_id' => import.id }, import, event_id, 'EnhancedImport::DestroyJob')
    end

    def owns_visits_or_tracks?(import)
      Visit.exists?(user_id: import.user_id, import_id: import.id) ||
        Track.exists?(user_id: import.user_id, import_id: import.id)
    end

    def oban?(type) = JobOwnership.oban?("command:#{type}")

    def forward(type, payload, import, event_id, producer)
      JobCommands.forward(type, payload, event_id:, aggregate_id: import.user_id, producer:)
      true
    end
  end
end
