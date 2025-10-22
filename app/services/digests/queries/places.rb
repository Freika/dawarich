# frozen_string_literal: true

class Digests::Queries::Places
  def initialize(user, date_range, limit: 3)
    @user = user
    @date_range = date_range
    @limit = limit
  end

  def call
    @user.visits
         .joins(:area)
         .where(started_at: @date_range)
         .select('visits.*, areas.name as area_name, EXTRACT(EPOCH FROM (visits.ended_at - visits.started_at)) as duration_seconds')
         .order('duration_seconds DESC')
         .limit(@limit)
         .map do |visit|
           {
             name: visit.area_name,
             duration_hours: (visit.duration_seconds / 3600.0).round(1),
             started_at: visit.started_at,
             ended_at: visit.ended_at
           }
         end
  end
end
