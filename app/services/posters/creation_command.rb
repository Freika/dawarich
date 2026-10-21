# frozen_string_literal: true

module Posters
  module CreationCommand
    COMMANDS = { 'posters.create' => { version: 1, sidekiq: ->(payload, _at) { sidekiq(payload) } } }.freeze
    HANDLERS = {
      'posters.created' => {
        guard: 'Owner-scoped created row; pending outbox dedupe or SET NX before the fallback enqueue, ' \
               'cleared on enqueue failure; repeats cannot enqueue a second incomplete poster job.',
        call: ->(payload) { follow_up(payload) }
      }
    }.freeze

    module_function

    def call(poster, locale = I18n.locale.to_s)
      payload = { 'poster_id' => poster.id, 'user_id' => poster.user_id, 'locale' => locale }
      JobCommands.produce('posters.create', payload,
                          aggregate_id: poster.id, producer: 'Poster#after_commit',
                          dedupe_key: "poster-create:#{poster.id}")
    end

    def follow_up(payload)
      poster = Poster.find_by(id: payload.fetch('poster_id'), user_id: payload.fetch('user_id'), status: :created)
      call(poster, payload.fetch('locale')) if poster
    end

    def sidekiq(payload)
      JobCommands.enqueue_after_commit(payload.fetch('locale')) do
        poster = Poster.find_by(id: payload.fetch('poster_id'), user_id: payload.fetch('user_id'), status: :created)
        next unless poster

        key = "poster-create:#{poster.id}"
        unless Rails.cache.write(key, 1, unless_exist: true, expires_in: nil)
          next if Rails.cache.exist?(key)

          raise 'the cache could not claim poster creation'
        end

        begin
          Posters::CreateJob.perform_later(poster.id)
        rescue StandardError
          Rails.cache.delete(key)
          raise
        end
      end
    end
  end
end
