# frozen_string_literal: true

module Imports
  module ExtractionCommands
    class Lost < StandardError; end
    class Busy < StandardError; end

    EXPECTED_KEYS = %w[user_id source source_blob_id event_id started_at].freeze
    HANDLERS = {
      'imports.extraction_requested' => {
        guard: 'Current actor/source/run before enqueue and each bounded extraction write or status transition.',
        call: ->(payload) { ExtractionCommands.call(payload, 'extract') }
      },
      'imports.extraction_destroy_requested' => {
        guard: 'Current actor/source/run before each removal batch, terminal reset or error transition.',
        call: ->(payload) { ExtractionCommands.call(payload, 'remove') }
      }
    }.freeze

    module_function

    def call(payload, action)
      expected = payload.slice(*EXPECTED_KEYS).merge('action' => action)
      import = Import.find_by(id: payload.fetch('import_id'))
      return unless matches?(import, expected)

      Time.use_zone(payload.fetch('time_zone')) do
        I18n.with_locale(payload.fetch('locale')) do
          klass = action == 'extract' ? EnhancedImport::ExtractJob : EnhancedImport::DestroyJob
          JobCommands.enqueue_after_commit(nil) { klass.perform_later(import.id, expected:) }
        end
      end
    end

    def with_session(import, expected)
      return yield unless expected

      ActiveRecord::Base.connection_pool.with_connection do |connection|
        key = connection.quote("phoenix-import:#{import.id}")
        locked = connection.select_value("SELECT pg_try_advisory_lock(hashtextextended(#{key},0))")
        raise Busy, 'Another import attempt is running' unless locked

        begin
          yield
        ensure
          connection.select_value("SELECT pg_advisory_unlock(hashtextextended(#{key},0))")
        end
      end
    end

    def effect!(import, expected)
      return yield unless expected

      ActiveRecord::Base.transaction do
        begin
          import.reload(lock: true)
        rescue ActiveRecord::RecordNotFound
          raise Lost, 'Import disappeared'
        end
        user = User.unscoped.lock('FOR SHARE').find_by(id: import.user_id)
        attachment = ActiveStorage::Attachment.lock('FOR SHARE').find_by(
          record_type: 'Import', record_id: import.id, name: 'file'
        )
        ActiveStorage::Blob.lock('FOR SHARE').find_by(id: attachment&.blob_id)
        import.association(:user).reset
        import.association(:file_attachment).reset
        raise Lost, 'Extraction identity changed' unless user && !user.deleted_at && matches?(import, expected)

        yield
      end
    end

    def matches?(import, expected)
      unless import && expected.is_a?(Hash) && !import.deleting? && import.user && import.user.deleted_at.nil?
        return false
      end
      return false unless import.user_id == expected['user_id'] && Import.sources[import.source] == expected['source']
      return false unless import.file_attachment&.blob_id == expected['source_blob_id']

      data = import.additional_data_extraction
      states = expected['action'] == 'extract' ? %w[pending running] : %w[running failed]
      data.is_a?(Hash) && states.include?(import.additional_data_extraction_status) &&
        data['phoenix_extraction_event'] == expected['event_id'] &&
        data['phoenix_extraction_action'] == expected['action'] && data['started_at'] == expected['started_at']
    end
  end
end
