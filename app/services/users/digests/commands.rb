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

      HANDLERS = {
        'digests.calculate_month' => {
          guard: 'Each calculation recomputes the period; a repeat costs one convergent calculation',
          call: ->(payload) { reverse_calculate('digests.calculate_month', payload) }
        },
        'digests.calculate_year' => {
          guard: 'Each calculation recomputes the period; a repeat costs one convergent calculation',
          call: ->(payload) { reverse_calculate('digests.calculate_year', payload) }
        },
        'digests.email_month' => {
          guard: 'The unchanged monthly email job checks sent_at, distance and the saved email toggle',
          call: ->(payload) { email(:monthly, payload) }
        },
        'digests.email_year' => {
          guard: 'The unchanged yearly email job checks sent_at, distance and the saved email toggle',
          call: ->(payload) { email(:yearly, payload) }
        }
      }.freeze

      module_function

      def reverse_calculate(type, payload)
        return unless User.exists?(id: payload.fetch('user_id'))

        JobCommands.produce(type, payload.except('run_at'), aggregate_id: payload.fetch('user_id'),
                            producer: name, scheduled_at: Time.zone.at(payload.fetch('run_at')))
      end

      def email(kind, payload)
        user = User.find_by(id: payload.fetch('user_id')) || return
        klass = kind == :monthly ? Monthly::EmailSendingJob : Yearly::EmailSendingJob
        args = [user.id, payload.fetch('year')]
        args << payload.fetch('month') if kind == :monthly

        Time.use_zone(payload.fetch('time_zone')) do
          I18n.with_locale(user.locale) { klass.perform_later(*args) }
        end
      end

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
