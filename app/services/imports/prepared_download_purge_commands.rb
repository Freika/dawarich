# frozen_string_literal: true

module Imports
  module PreparedDownloadPurgeCommands
    HANDLERS = {
      'imports.prepared_download_purge' => {
        guard: 'Exact immutable server receipt; current owner if import exists; zero blob attachments.',
        call: ->(payload) { PreparedDownloadPurgeCommands.call(payload) }
      }
    }.freeze

    module_function

    def call(payload)
      fields = %w[blob_id import_id user_id source_blob_id]
      return unless fields.all? { |field| payload[field].is_a?(Integer) && payload[field].positive? }

      blob = ActiveStorage::Blob.find_by(id: payload.fetch('blob_id'))
      return unless blob

      blob.with_lock do
        receipt = ActiveRecord::Base.connection.select_value(<<~SQL.squish)
          SELECT blob_id FROM phoenix.import_blob_purges
          WHERE blob_id=#{blob.id} AND import_id=#{payload.fetch('import_id')}
            AND user_id=#{payload.fetch('user_id')} AND source_blob_id=#{payload.fetch('source_blob_id')}
        SQL
        return unless receipt

        import = Import.find_by(id: payload.fetch('import_id'))
        return if import && import.user_id != payload.fetch('user_id')
        return if blob.attachments.exists?

        JobCommands.enqueue_after_commit(nil) { blob.purge_later }
      end
    end
  end
end
