# frozen_string_literal: true

module Imports
  module PostprocessingCommands
    HANDLERS = {
      'imports.postprocessing_step' => {
        guard: 'Owner-scoped current import; stats converge, achievements debounce, track/counter commands ' \
               'route through their current owner. Repeated visit/extraction enqueues can cost one extra pass.',
        call: ->(payload) { PostprocessingCommands.call(payload) }
      }
    }.freeze

    module_function

    def call(payload)
      import = Import.find_by(id: payload.fetch('import_id'), user_id: payload.fetch('user_id'))
      return unless import && import.user.deleted_at.nil? && !import.deleting?

      Time.use_zone(payload.fetch('time_zone')) do
        I18n.with_locale(payload.fetch('locale')) { dispatch(import, payload) }
      end
    end

    def dispatch(import, payload)
      case payload.fetch('step')
      when 'schedule_stats'
        payload.fetch('months').each { |year, month| Stats::CalculatingJob.perform_later(import.user_id, year, month) }
        Achievements::CheckJob.schedule(import.user_id, oldest_timestamp: payload.fetch('oldest_timestamp'))
      when 'schedule_visit_suggesting'
        return unless import.user.safe_settings.visits_suggestions_enabled?

        VisitSuggestingJob.perform_later(user_id: import.user_id,
                                         start_at: Time.iso8601(payload.fetch('start_at')),
                                         end_at: Time.iso8601(payload.fetch('end_at')))
      when 'command'
        command(import, payload)
      when 'extract'
        if import.completed? && import.additional_data_extraction_pending?
          EnhancedImport::ExtractJob.perform_later(import.id)
        end
      else
        raise ArgumentError, 'Unsupported import postprocessing step'
      end
    end

    def command(import, payload)
      type = payload.fetch('command_type')
      args = payload.fetch('command_payload')
      aggregate = payload.fetch('aggregate_id')
      valid = case type
              when 'imports.update_points_count'
                args == { 'import_id' => import.id } && aggregate == import.id
              when 'tracks.generate_range'
                args['user_id'] == import.user_id && args['import_id'] == import.id && aggregate == import.user_id
              else
                false
              end
      raise ArgumentError, 'Import postprocessing command identity mismatch' unless valid

      if type == 'imports.update_points_count'
        ImportCommands.update_points_count(import.id, producer: 'Phoenix Imports Postprocessing')
      else
        JobCommands.produce(type, args, aggregate_id: aggregate, producer: 'Phoenix Imports Postprocessing')
      end
    end

    private_class_method :dispatch, :command
  end
end
