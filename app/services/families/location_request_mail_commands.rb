# frozen_string_literal: true

module Families
  module LocationRequestMailCommands
    COMMANDS = {
      'mail.family_location_request' => {
        version: 1,
        sidekiq: lambda { |payload, _at|
          ::JobCommands.enqueue_after_commit(nil) do
            ActiveJob::Base.logger.silence(Logger::UNKNOWN) do
              RailsCommands::Registry.handler('family_location_request_mail').call(payload)
            end
          end
        }
      }
    }.freeze
  end
end
