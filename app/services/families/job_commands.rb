# frozen_string_literal: true

module Families
  module JobCommands
    HANDLERS = {
      'mail.family_lapse' => {
        guard: 'The unchanged lapse mail leaf checks its marker; a repeat costs one convergent enqueue',
        call: ->(payload) { lapse_notice(payload) }
      }
    }.freeze

    module_function

    def lapse_notice(payload)
      user_id = payload.fetch('user_id')
      family_id = payload.fetch('family_id')
      return unless User.exists?(id: user_id) && Family.exists?(id: family_id)

      ::JobCommands.produce('mail.family_lapse', payload, aggregate_id: user_id, producer: name,
                            dedupe_key: "family-lapse:#{family_id}:#{user_id}:#{payload.fetch('lapse_at')}")
    end
  end
end
