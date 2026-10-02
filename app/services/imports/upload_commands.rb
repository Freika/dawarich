# frozen_string_literal: true

module Imports
  module UploadCommands
    HANDLERS = {
      'imports.upload_created' => {
        guard: 'Current import/user identity, active user, captured upload zone; completed/deleting rows ignored.',
        call: ->(payload) { UploadCommands.call(payload) }
      }
    }.freeze

    module_function

    def call(payload)
      import = Import.find_by(id: payload.fetch('import_id'), user_id: payload.fetch('user_id'))
      return unless import && import.user.deleted_at.nil? && !import.completed? && !import.deleting?

      Time.use_zone(payload.fetch('time_zone')) do
        I18n.with_locale(import.user.locale) do
          JobCommands.enqueue_after_commit(nil) { Import::ProcessJob.perform_later(import.id) }
        end
      end
    end
  end
end
