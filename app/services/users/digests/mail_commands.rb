# frozen_string_literal: true

module Users
  module Digests
    module MailCommands
      COMMANDS = {
        'mail.digest.monthly' => { version: 1, sidekiq: ->(payload, at) { legacy(:monthly, payload, at) } },
        'mail.digest.yearly' => { version: 1, sidekiq: ->(payload, at) { legacy(:yearly, payload, at) } }
      }.freeze

      module_function

      def enqueue(&block)
        ActiveJob::Base.logger.silence(Logger::UNKNOWN, &block)
      end

      def forward(kind, user_id, year, month, event_id:, producer:)
        payload = { 'user_id' => user_id, 'year' => year.to_i, 'time_zone' => Time.zone.name,
                    'locale' => I18n.locale.to_s }
        payload['month'] = month.to_i if kind == :monthly
        JobCommands.forward("mail.digest.#{kind}", payload, event_id:, aggregate_id: user_id, producer:)
      end

      def legacy(kind, payload, at)
        klass = kind == :monthly ? Monthly::EmailSendingJob : Yearly::EmailSendingJob
        args = [payload.fetch('user_id'), payload.fetch('year')]
        args << payload.fetch('month') if kind == :monthly
        JobCommands.enqueue_after_commit(payload.fetch('locale')) do
          Time.use_zone(payload.fetch('time_zone')) { enqueue { klass.set(wait_until: at).perform_later(*args) } }
        end
      end
    end
  end
end
