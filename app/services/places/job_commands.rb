# frozen_string_literal: true

module Places
  module JobCommands
    JOBS = {
      'places.delete_if_orphan' => [DeleteIfOrphanJob, 'place_id'],
      'places.orphan_cleanup' => [OrphanCleanupJob, 'user_id'],
      'places.name_fetch' => [NameFetchingJob, 'place_id'],
      'places.bulk_name_fetch' => [BulkNameFetchingJob, nil]
    }.freeze

    COMMANDS = JOBS.to_h do |type, (klass, id_key)|
      [type, { version: 1, sidekiq: ->(payload, at) { enqueue(klass, payload, id_key, at) } }]
    end.freeze

    HANDLERS = {
      'places_delete_if_orphan' => {
        guard: 'Owned leaf publication; repeated orphan deletion rechecks eligibility',
        call: ->(payload) { reverse_places('places.delete_if_orphan', payload) }
      },
      'place_name_fetch' => {
        guard: 'Owned leaf publication; a repeat costs one provider lookup',
        call: ->(payload) { reverse_places('places.name_fetch', payload) }
      },
      'places_orphan_cleanup' => {
        guard: 'User orphan deletion converges after the retained reference checks',
        call: ->(payload) { reverse_user(payload) }
      },
      'places_bulk_name_fetch' => {
        guard: 'Default name selection converges; repeated publication costs another lookup',
        call: ->(_payload) { ::JobCommands.produce('places.bulk_name_fetch', {}, aggregate_id: nil, producer: name) }
      }
    }.freeze

    module_function

    def execute(type, id = nil, job_id:)
      forwarded = ActiveRecord::Base.transaction do
        next false unless JobOwnership.lock_owner("command:#{type}") == :oban

        id_key = JOBS.fetch(type).last
        payload = id_key ? { id_key => id } : {}
        if id_key == 'place_id'
          user_id = Place.where(id: id).pick(:user_id)
          next false unless user_id

          payload['user_id'] = user_id
        end
        event = Digest::UUID.uuid_v5(Digest::UUID::URL_NAMESPACE, "#{type}:#{job_id}")
        ::JobCommands.forward(type, payload, event_id: event, aggregate_id: id, producer: name)
        true
      end
      yield unless forwarded
    end

    def enqueue(klass, payload, id_key, at)
      ::JobCommands.enqueue_after_commit(nil) do
        klass.set(wait_until: at).perform_later(*(id_key ? [payload.fetch(id_key)] : []))
      end
    end

    def reverse_places(type, payload)
      user_id = payload.fetch('user_id')
      return unless User.exists?(id: user_id)

      ids = payload['place_ids'] || [payload.fetch('place_id')]
      Place.where(user_id: user_id, id: ids.uniq).pluck(:id).each do |id|
        ::JobCommands.produce(type, { 'user_id' => user_id, 'place_id' => id }, aggregate_id: id, producer: name)
      end
    end

    def reverse_user(payload)
      id = payload.fetch('user_id')
      return unless User.exists?(id: id)

      ::JobCommands.produce('places.orphan_cleanup', { 'user_id' => id }, aggregate_id: id, producer: name)
    end
  end
end
