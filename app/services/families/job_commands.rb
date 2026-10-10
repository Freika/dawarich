# frozen_string_literal: true

module Families
  module JobCommands
    COMMANDS = {
      'families.auto_create' => {
        version: 1,
        sidekiq: ->(payload, at) { enqueue(AutoCreationJob, payload, 'user_id', at) }
      },
      'families.member_sync' => {
        version: 1,
        sidekiq: ->(payload, at) { enqueue(MemberSyncJob, payload, 'family_id', at) }
      }
    }.freeze

    HANDLERS = {
      'mail.family_lapse' => {
        guard: 'The unchanged lapse mail leaf checks its marker; a repeat costs one convergent enqueue',
        call: ->(payload) { lapse_notice(payload) }
      }
    }.freeze

    module_function

    def execute(kind, id, job_id:)
      type = "families.#{kind}"
      ActiveRecord::Base.transaction do
        if JobOwnership.lock_owner("command:#{type}") == :oban
          payload = { kind == 'auto_create' ? 'user_id' : 'family_id' => id, 'time_zone' => Time.zone.name }
          payload['locale'] = I18n.locale.to_s if kind == 'member_sync'
          event_id = Digest::UUID.uuid_v5(Digest::UUID::URL_NAMESPACE, "#{type}:#{job_id}")
          ::JobCommands.forward(type, payload, event_id: event_id, aggregate_id: id, producer: name)
        else
          yield
        end
      end
    end

    def enqueue(klass, payload, id_key, at)
      ::JobCommands.enqueue_after_commit(payload['locale']) do
        Time.use_zone(payload.fetch('time_zone')) { klass.set(wait_until: at).perform_later(payload.fetch(id_key)) }
      end
    end

    def lapse_notice(payload)
      user_id = payload.fetch('user_id')
      family_id = payload.fetch('family_id')
      return unless User.exists?(id: user_id) && Family.exists?(id: family_id)

      ::JobCommands.produce('mail.family_lapse', payload, aggregate_id: user_id, producer: name,
                            dedupe_key: "family-lapse:#{family_id}:#{user_id}:#{payload.fetch('lapse_at')}")
    end
  end
end
