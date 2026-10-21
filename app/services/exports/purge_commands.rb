# frozen_string_literal: true

module Exports
  module PurgeCommands
    HANDLERS = {
      'exports.purge' => {
        guard: 'Deleted export and no surviving blob attachments; repeats find purged blobs absent.',
        call: ->(payload) { call(payload) }
      }
    }.freeze

    module_function

    def call(payload)
      return if Export.exists?(id: payload.fetch('export_id'))

      ActiveStorage::Blob.where(id: payload.fetch('blob_ids')).find_each do |blob|
        blob.with_lock do
          next if blob.attachments.exists?

          JobCommands.enqueue_after_commit(nil) { blob.purge_later }
        end
      end
    end
  end
end
