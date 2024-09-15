# frozen_string_literal: true

class Visits::Suggest
  include Rails.application.routes.url_helpers

  attr_reader :points, :user, :start_at, :end_at

  def initialize(user, start_at:, end_at:)
    @start_at = start_at.to_i
    @end_at = end_at.to_i
    @points = user.tracked_points.not_visited.order(timestamp: :asc).where(timestamp: start_at..end_at)
    @user = user
  end

  def call
    prepared_visits = Visits::Prepare.new(points).call

    visited_places = create_places(prepared_visits)
    visits = create_visits(visited_places)

    create_visits_notification(user)

    nil unless reverse_geocoding_enabled?

    reverse_geocode(visits)
  end

  private

  def create_places(prepared_visits)
    prepared_visits.flat_map do |date|
      date[:visits] = handle_visits(date[:visits])

      date
    end
  end

  def create_visits(visited_places)
    visited_places.flat_map do |date|
      date[:visits].map do |visit_data|
        ActiveRecord::Base.transaction do
          search_params = {
            user_id:    user.id,
            duration:   visit_data[:duration],
            started_at: Time.zone.at(visit_data[:points].first.timestamp)
          }

          if visit_data[:area].present?
            search_params[:area_id] = visit_data[:area].id
          elsif visit_data[:place].present?
            search_params[:place_id] = visit_data[:place].id
          end

          visit = Visit.find_or_initialize_by(search_params)
          visit.name = visit_data[:place]&.name || visit_data[:area]&.name if visit.name.blank?
          visit.ended_at = Time.zone.at(visit_data[:points].last.timestamp)
          visit.save!

          visit_data[:points].each { |point| point.update!(visit_id: visit.id) }

          visit
        end
      end
    end
  end

  def reverse_geocode(visits)
    visits.each(&:async_reverse_geocode)
  end

  def reverse_geocoding_enabled?
    ::REVERSE_GEOCODING_ENABLED && ::PHOTON_API_HOST.present?
  end

  def create_visits_notification(user)
    content = <<~CONTENT
      New visits have been suggested based on your location data from #{Time.zone.at(start_at)} to #{Time.zone.at(end_at)}. You can review them on the <a href="#{visits_path}" class="link">Visits</a> page.
    CONTENT

    user.notifications.create!(
      kind: :info,
      title: 'New visits suggested',
      content:
    )
  end

  def create_place(visit)
    place = Place.find_or_initialize_by(
      latitude: visit[:latitude].to_f.round(5),
      longitude: visit[:longitude].to_f.round(5)
    )

    place.name = Place::DEFAULT_NAME
    place.source = Place.sources[:manual]

    place.save!

    place
  end

  def handle_visits(visits)
    visits.map do |visit|
      area = Area.near([visit[:latitude], visit[:longitude]], 0.100).first

      if area.present?
        visit.merge(area:)
      else
        place = create_place(visit)

        visit.merge(place:)
      end
    end
  end
end
