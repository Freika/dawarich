# frozen_string_literal: true

module Users
  module Digests
    module Commands
      COMMANDS = {
        'digests.calculate_month' => {
          version: 1,
          sidekiq: ->(payload, at) { JobCommands.enqueue_after_commit(nil) { calculate(:monthly, payload, at) } }
        },
        'digests.calculate_year' => {
          version: 1,
          sidekiq: ->(payload, at) { JobCommands.enqueue_after_commit(nil) { calculate(:yearly, payload, at) } }
        }
      }.freeze

      module_function

      def calculate(kind, payload, at)
        klass = kind == :monthly ? Monthly::CalculatingJob : Yearly::CalculatingJob
        args = [payload.fetch('user_id'), payload.fetch('year')]
        args << payload.fetch('month') if kind == :monthly

        Time.use_zone(payload.fetch('time_zone')) do
          klass.set(wait_until: at).perform_later(*args)
        end
      end
    end
  end
end
