# frozen_string_literal: true

class Digests::Queries::Trips
  def initialize(user, date_range)
    @user = user
    @date_range = date_range
  end

  def call
    @user.trips
         .where('started_at <= ? AND ended_at >= ?', @date_range.end, @date_range.begin)
         .order(started_at: :desc)
         .map do |trip|
           {
             id: trip.id,
             name: trip.name,
             started_at: trip.started_at,
             ended_at: trip.ended_at,
             distance_km: trip.distance || 0,
             countries: trip.visited_countries || [],
             photo_previews: trip.photo_previews.first(3)
           }
         end
  end
end
