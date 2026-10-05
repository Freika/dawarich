# frozen_string_literal: true

module Users
  module DataExportLegacy
    module_function

    def perform(user, event_id:, zone:, locale:)
      error = nil
      result = JobOwnership.with_owner('command:users.export_data') do
        Users::ExportData.new(user).export
      rescue StandardError => e
        error = e
        nil
      end
      raise error if error
      return result unless result == :not_owner

      DataCommands.forward(user, event_id:, zone:, locale:)
    end
  end
end
