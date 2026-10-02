# frozen_string_literal: true

module Imports
  module GpxLegacy
    class Busy < StandardError; end

    module_function

    def perform(import, event_id:)
      PhoenixLease.hold("import:#{import.id}", Busy.new('Another import attempt is running')) do
        action = ActiveRecord::Base.transaction { admission(import, event_id) }
        I18n.with_locale(import.user.locale) { import.process! } if action == :process
      end
    end

    def admission(import, event_id)
      owner = JobOwnership.lock_owner('command:imports.process_gpx')
      import.reload(lock: true)
      user = User.lock('FOR SHARE').find_by(id: import.user_id)
      return if import.deleting? || (import.gpx? && import.completed?) || !user || user.deleted_at

      if owner == :oban && ImportCommands.native_gpx?(import)
        payload = { 'import_id' => import.id, 'user_id' => import.user_id, 'time_zone' => Time.zone.name }
        JobCommands.forward('imports.process_gpx', payload, event_id:, aggregate_id: import.id,
                            producer: 'Import::ProcessJob', dedupe_key: "process-gpx:#{import.id}")
        :forwarded
      else
        :process
      end
    end
    private_class_method :admission
  end
end
