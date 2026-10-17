# frozen_string_literal: true

module Users
  module DataCommands
    TYPE = 'users.export_data'
    IMPORT_TYPE = 'users.import_data'
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
      },
      IMPORT_TYPE => {
        version: 1,
        sidekiq: lambda { |payload, at|
          JobCommands.enqueue_after_commit(payload.fetch('locale')) do
            Time.use_zone(payload.fetch('time_zone')) do
              Users::ImportDataJob.set(wait_until: at).perform_later(payload.fetch('import_id'))
            end
          end
        }
      }
    }.freeze

    HANDLERS = {
      TYPE => {
        guard: 'Each GET queues a backup command; worker event identity fences repeated delivery',
        call: lambda { |payload|
          JobCommands.produce(TYPE, payload, aggregate_id: payload.fetch('user_id'),
                                        producer: 'Phoenix SettingsUsersExport')
        }
      },
      IMPORT_TYPE => {
        guard: 'Pending restore commands deduplicate by import id; the worker fences archive identity',
        call: ->(payload) { produce_import(payload, producer: 'Phoenix UserDataImport') }
      }
    }.freeze

    module_function

    def import_payload(import, zone: Time.zone.name, locale: I18n.locale.to_s)
      { 'import_id' => import.id, 'user_id' => import.user_id, 'time_zone' => zone, 'locale' => locale }
    end

    def produce_import(payload, producer:)
      JobCommands.produce(IMPORT_TYPE, payload, aggregate_id: payload.fetch('import_id'), producer:,
                          dedupe_key: "user-data-import:#{payload.fetch('import_id')}")
    end

    def process_import(import, producer:)
      produce_import(import_payload(import), producer:)
    end

    def forward_import(import, event_id:, zone:, locale:)
      JobOwnership.with_owner("command:#{IMPORT_TYPE}", :oban) do
        JobCommands.forward(IMPORT_TYPE, import_payload(import, zone:, locale:), event_id:,
                            aggregate_id: import.id, producer: 'Users::ImportDataJob')
      end
    end

    def forward(user, event_id:, zone:, locale:)
      payload = { 'user_id' => user.id, 'time_zone' => zone, 'locale' => locale }
      JobOwnership.with_owner("command:#{TYPE}", :oban) do
        JobCommands.forward(TYPE, payload, event_id:, aggregate_id: user.id, producer: 'Users::ExportDataJob')
      end
    end
  end
end
