# frozen_string_literal: true

module Analytics
  # Records import_succeeded once per upload, when its last file finishes and
  # at least one file completed with points for the map. A ZIP upload is one
  # result over the imports extracted from it: 'partial' when some failed.
  # The event is stored in the same job that finishes the import and sent to
  # Rybbit by its own job, so a closed tab or an unreachable Rybbit loses
  # nothing and fails nothing.
  class ImportSucceeded
    def initialize(import)
      @import = import
    end

    def call
      return if DawarichSettings.self_hosted? || @import.demo?
      return if upload_imports.any? { |import| import.created? || import.processing? }
      return unless upload_imports.any?(&:completed?)
      return unless Point.where(import_id: upload_imports.map(&:id)).exists?

      event = AnalyticsEvent.record(
        user: @import.user, event: :import_succeeded, dedup_key: "import_succeeded:#{upload_id}",
        properties: { result: upload_imports.all?(&:completed?) ? 'complete' : 'partial', files: upload_imports.size }
      )
      Analytics::DeliverEventJob.perform_later(event.id) if event
    rescue StandardError => e
      ExceptionReporter.call(e, 'Failed to record import_succeeded')
    end

    private

    def upload_id
      @import.archive_import_id || @import.id
    end

    def upload_imports
      @upload_imports ||=
        if @import.archive_import_id
          Import.where(user_id: @import.user_id, archive_import_id: @import.archive_import_id).to_a
        else
          [@import]
        end
    end
  end
end
