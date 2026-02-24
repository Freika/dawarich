# frozen_string_literal: true

class Visits::Suggest
  attr_reader :points, :user, :start_at, :end_at

  def initialize(user, start_at:, end_at:)
    @start_at = start_at.to_i
    @end_at = end_at.to_i
    @points = user.points.not_visited.order(timestamp: :asc).where(timestamp: start_at..end_at)
    @user = user
  end

  def call
    visits = Visits::SmartDetect.new(user, start_at:, end_at:).call
    return visits if visits.empty?

    create_visits_notification(user)
    if DawarichSettings.reverse_geocoding_enabled?
      visits.filter_map(&:place_id).uniq.each do |place_id|
        ReverseGeocodingJob.perform_later('place', place_id)
      end
    end

    visits
  rescue StandardError => e
    # create a notification with stacktrace and what arguments were used
    user.notifications.create!(
      kind: :error,
      title: 'Error suggesting visits',
      content: "Error suggesting visits: #{e.message}\n#{e.backtrace.join("\n")}"
    )

    ExceptionReporter.call(e)
  end

  private

  def create_visits_notification(user)
    content = <<~CONTENT
      New visits have been suggested based on your location data from #{Time.zone.at(start_at)} to #{Time.zone.at(end_at)}. You can review them on the <a href="/visits" class="link">Visits</a> page.
    CONTENT

    user.notifications.create!(
      kind: :info,
      title: 'New visits suggested',
      content:
    )
  end
end
