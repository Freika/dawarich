# frozen_string_literal: true

module EnhancedImport
  module CardBroadcaster
    module_function

    def call(import)
      Turbo::StreamsChannel.broadcast_replace_to(
        "import_#{import.id}_extraction",
        target: "import-#{import.id}-extraction",
        partial: 'imports/extraction_card',
        locals: { import: import.reload }
      )
    rescue StandardError => e
      Rails.logger.warn("[EnhancedImport::CardBroadcaster] card broadcast failed import_id=#{import.id}: #{e.message}")
    end
  end
end
