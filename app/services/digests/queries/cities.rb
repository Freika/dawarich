# frozen_string_literal: true

class Digests::Queries::Cities
  def initialize(user, date_range, limit: 5)
    @user = user
    @date_range = date_range
    @limit = limit
    @start_timestamp = date_range.begin.to_i
    @end_timestamp = date_range.end.to_i
  end

  def call
    @user.points
         .where(timestamp: @start_timestamp..@end_timestamp)
         .where.not(city: nil)
         .group(:city)
         .count
         .sort_by { |_city, count| -count }
         .first(@limit)
         .map { |city, count| { name: city, visits: count } }
  end
end
