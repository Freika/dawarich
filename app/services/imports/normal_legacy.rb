# frozen_string_literal: true

module Imports
  module NormalLegacy
    class Busy < StandardError; end

    module_function

    def perform(import, event_id:)
      PhoenixLease.hold("import:#{import.id}", Busy.new('Another import attempt is running')) do
        action = ActiveRecord::Base.transaction { admission(import, event_id) }
        I18n.with_locale(import.user.locale) { import.process! } if action == :process
      end
    end

    def admission(import, event_id)
      import.reload(lock: true)
      user = User.lock('FOR SHARE').find_by(id: import.user_id)
      return if import.deleting? || !user || user.deleted_at

      gpx = ImportCommands.native_gpx?(import)
      type = gpx ? 'imports.process_gpx' : ProcessCommands::TYPE
      owner = JobOwnership.lock_owner("command:#{type}")
      if owner == :oban && (gpx || ProcessCommands.native?(import))
        ProcessCommands.forward(import, event_id:)
        :forwarded
      else
        :process
      end
    end
    private_class_method :admission
  end
end
