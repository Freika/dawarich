# frozen_string_literal: true

module Imports
  module DownloadCommands
    class Busy < StandardError; end

    HANDLERS = {
      'imports.prepare_download' => {
        guard: 'Current active actor/source; explicit native fallback prevents reforward loops.',
        call: ->(payload) { DownloadCommands.call(payload) }
      }
    }.freeze

    module_function

    def call(payload)
      import = Import.find_by(id: payload.fetch('import_id'), user_id: payload.fetch('user_id'))
      return unless available?(import, payload.fetch('source_blob_id'))

      JobCommands.enqueue_after_commit(nil) do
        Imports::PrepareDownloadJob.perform_later(import.id, payload.fetch('source_blob_id'),
                                                  native_fallback: payload.fetch('native_fallback', false),
                                                  expected_user_id: import.user_id)
      end
    end

    def perform(import_id, source_blob_id, event_id:, native_fallback:, expected_user_id: nil)
      PhoenixLease.hold("import-download:#{Integer(import_id)}",
                        Busy.new('Another download preparation is running')) do
        import, owner = ActiveRecord::Base.transaction do
          current_owner = JobOwnership.lock_owner('command:imports.prepare_download')
          current = Import.find_by(id: import_id)
          current&.lock!
          next unless available?(current,
                                 source_blob_id) && (!expected_user_id || current.user_id == expected_user_id)

          if current_owner == :oban && !native_fallback
            JobCommands.forward('imports.prepare_download',
                                { 'import_id' => current.id, 'user_id' => current.user_id,
                                  'source_blob_id' => source_blob_id },
                                event_id:, aggregate_id: current.id, producer: 'Imports::PrepareDownloadJob',
                                dedupe_key: "prepare-download:#{event_id}")
            next
          end
          [current, current_owner]
        end
        next unless import

        actor = import.user_id
        snapshot = import.file.blob.attributes.slice('id', 'key', 'filename', 'byte_size', 'checksum', 'service_name')
        fence = lambda do |&effect|
          ActiveRecord::Base.transaction do
            unless JobOwnership.lock_owner('command:imports.prepare_download') == owner
              raise Busy,
                    'Download ownership changed'
            end

            import.reload(lock: true)
            import.user.lock!
            raise Busy, 'Download source changed' unless available?(import, source_blob_id) && import.user_id == actor

            blob = import.file.blob.reload(lock: true)
            raise Busy, 'Download source changed' unless blob.attributes.slice(*snapshot.keys) == snapshot

            effect.call
          end
        end
        Imports::Download.new(import, fence:).prepare
      end
    end

    def available?(import, source_blob_id)
      import && !import.deleting? && import.user.deleted_at.nil? && import.file.attached? &&
        import.file.blob_id == source_blob_id
    end
    private_class_method :available?
  end
end
