# frozen_string_literal: true

module Users
  module DataCommands
    TYPE = 'users.export_data'
    COMMANDS = {
      TYPE => {
        version: 1,
        sidekiq: lambda { |payload, at|
          JobCommands.enqueue_after_commit(payload.fetch('locale')) do
            Time.use_zone(payload.fetch('time_zone')) do
              Users::ExportDataJob.set(wait_until: at).perform_later(payload.fetch('user_id'))
            end
          end
        }
      }
    }.freeze

    module_function

    def forward(user, event_id:, zone:, locale:)
      payload = { 'user_id' => user.id, 'time_zone' => zone, 'locale' => locale }
      JobOwnership.with_owner("command:#{TYPE}", :oban) do
        JobCommands.forward(TYPE, payload, event_id:, aggregate_id: user.id, producer: 'Users::ExportDataJob')
      end
    end
  end
end
