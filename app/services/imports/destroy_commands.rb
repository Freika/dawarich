# frozen_string_literal: true

module Imports
  module DestroyCommands
    HANDLERS = {
      'imports.destroy_requested' => {
        guard: 'Exact actor and event; legacy perform rechecks the lock and owner.',
        call: ->(payload) { requested(payload) }
      },
      'imports.destroy_status' => {
        guard: 'Re-render current owner-scoped status; never restore a stale snapshot.',
        call: ->(payload) { status(payload) }
      },
      'imports.destroy_callbacks' => {
        guard: 'Proven actor; repeats schedule convergent owned-row callbacks.',
        call: ->(payload) { callbacks(payload) }
      },
      'imports.destroy_achievements' => {
        guard: 'Proven actor; real Redis debounce coalesces repeated checks.',
        call: ->(payload) { achievements(payload) }
      },
      'imports.destroy_stats' => {
        guard: 'Exact terminal tombstone; current-history bulk sweep converges.',
        call: ->(payload) { stats(payload) }
      },
      'imports.destroy_complete' => {
        guard: 'Exact terminal tombstone; repeats target the same absent row.',
        call: ->(payload) { complete(payload) }
      },
      'imports.destroy_terminal' => {
        guard: 'Actor/event handback under the shared lock; cleanup converges.',
        call: ->(payload) { terminal(payload) }
      }
    }.freeze

    module_function

    def requested(payload)
      row = proof(payload, exact_event: true)
      return unless row

      import = Import.find_by(id: payload.fetch('import_id'), user_id: payload.fetch('user_id'))
      return unless import && User.exists?(id: import.user_id) && row['phase'] != 'removed'

      JobCommands.enqueue_after_commit(nil) do
        Imports::DestroyJob.perform_later(import.id, expected_user_id: import.user_id,
                                                    event_id: payload.fetch('event_id'))
      end
    end

    def status(payload)
      return unless proof(payload)

      import = Import.find_by(id: payload.fetch('import_id'), user_id: payload.fetch('user_id'))
      return unless import && User.exists?(id: import.user_id)

      I18n.with_locale(import.user.locale) do
        ImportsChannel.broadcast_to(import.user, action: 'status_update',
                                                 import: { id: import.id, status: import.status })
        Turbo::StreamsChannel.broadcast_replace_to(
          [import.user, :imports], target: ActionView::RecordIdentifier.dom_id(import),
          partial: 'imports/table_row', locals: { import:, timezone: import.user.safe_settings.timezone }
        )
      end
    end

    def callbacks(payload)
      return unless usable_actor?(payload)

      case payload.fetch('step')
      when 'places_cleanup'
        Place.where(id: payload.fetch('place_ids'), user_id: payload.fetch('user_id')).pluck(:id).each do |id|
          Places::DeleteIfOrphanJob.perform_later(id)
        end
      when 'reclassify_tracks'
        Track.where(id: payload.fetch('track_ids'), user_id: payload.fetch('user_id')).pluck(:id).each do |id|
          JobCommands.produce('transportation.reclassify_track',
                              { 'track_id' => id, 'report_progress' => false, 'user_id' => nil },
                              aggregate_id: id, producer: 'Phoenix Imports Destroy')
        end
      else
        raise ArgumentError, 'Unsupported import destruction callback'
      end
    end

    def achievements(payload)
      return unless usable_actor?(payload)

      Achievements::CheckJob.schedule(payload.fetch('user_id'), oldest_timestamp: payload.fetch('oldest_timestamp'))
    end

    def stats(payload)
      return unless terminal_proof(payload)

      Stats::BulkCalculator.new(payload.fetch('user_id')).call
    end

    def complete(payload)
      return unless terminal_proof(payload)

      user = User.find(payload.fetch('user_id'))
      ImportsChannel.broadcast_to(user, action: 'delete', import: { id: payload.fetch('import_id') })
      Turbo::StreamsChannel.broadcast_remove_to([user, :imports], target: "import_#{payload.fetch('import_id')}")
    end

    def terminal(payload)
      return unless valid?(payload)

      Imports::DestroyLegacy.with_lock(payload.fetch('import_id')) do
        row = terminal_proof(payload)
        next unless row && row['native_fallback']

        context = row['context'].is_a?(String) ? JSON.parse(row['context']) : row['context']
        ids = Track.where(id: context.fetch('track_ids', []), user_id: payload.fetch('user_id')).pluck(:id)
        Track.delete_orphaned(ids)
        stats(payload)
        complete(payload)
      end
    end

    def usable_actor?(payload)
      return false unless proof(payload)
      return false unless User.exists?(id: payload.fetch('user_id'))

      import = Import.find_by(id: payload.fetch('import_id'))
      !import || import.user_id == payload.fetch('user_id')
    end

    def terminal_proof(payload)
      row = proof(payload, exact_event: true)
      return unless row && row['phase'] == 'removed' && User.exists?(id: payload.fetch('user_id'))
      return if Import.exists?(id: payload.fetch('import_id'))

      row
    end

    def proof(payload, exact_event: false)
      return unless valid?(payload)

      row = Imports::DestroyLegacy.receipt(payload.fetch('import_id'))
      return unless row && row['user_id'].to_i == payload.fetch('user_id')
      return if exact_event && row['event_id'] != payload.fetch('event_id')

      row
    end

    def valid?(payload)
      %w[import_id user_id].all? { |key| payload[key].is_a?(Integer) && payload[key].positive? } &&
        payload['event_id'].is_a?(String) &&
        payload['event_id'].match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
    end

    private_class_method :usable_actor?, :terminal_proof, :proof, :valid?
  end
end
