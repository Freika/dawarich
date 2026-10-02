# frozen_string_literal: true

module Visits
  module Commands
    SUGGEST = 'visits.suggest'
    REDETECT = 'visits.full_history_redetect'

    module_function

    def forward_suggest(user, start_time, end_time, event_id:)
      return false unless oban?(SUGGEST)

      payload = {
        'user_id' => user.id, 'start_at' => start_time.to_i, 'end_at' => end_time.to_i,
        'stepping' => start_time.is_a?(ActiveSupport::TimeWithZone) ? 'calendar' : 'fixed',
        'time_zone' => Time.zone.tzinfo.name, 'plan_restricted' => user.plan_restricted? || false
      }
      JobCommands.forward(SUGGEST, payload, event_id:, aggregate_id: user.id, producer: 'VisitSuggestingJob')
      true
    end

    def forward_redetect(user_id, event_id:)
      return false unless oban?(REDETECT)

      user = User.find_by(id: user_id)
      payload = { 'user_id' => Integer(user_id), 'time_zone' => Time.zone.tzinfo.name,
                  'plan_restricted' => user&.plan_restricted? || false }
      JobCommands.forward(REDETECT, payload, event_id:, aggregate_id: Integer(user_id),
                                              producer: 'Visits::FullHistoryRedetectJob')
      true
    end

    def job_arguments(payload)
      zone = ActiveSupport::TimeZone[payload.fetch('time_zone')]
      start_at = zone.at(payload.fetch('start_at'))
      end_at = zone.at(payload.fetch('end_at'))
      return { user_id: payload.fetch('user_id'), start_at: start_at, end_at: end_at } if payload['stepping'] == 'fixed'

      { user_id: payload.fetch('user_id'), start_at: start_at.iso8601, end_at: end_at.iso8601 }
    end

    def oban?(type) = JobOwnership.oban?("command:#{type}")
  end
end
