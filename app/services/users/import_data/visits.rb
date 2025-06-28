# frozen_string_literal: true

class Users::ImportData::Visits
  def initialize(user, visits_data)
    @user = user
    @visits_data = visits_data
  end

  def call
    return 0 unless visits_data.is_a?(Array)

    Rails.logger.info "Importing #{visits_data.size} visits for user: #{user.email}"

    visits_created = 0

    visits_data.each do |visit_data|
      next unless visit_data.is_a?(Hash)

      # Check if visit already exists (match by name, timestamps, and place reference)
      existing_visit = find_existing_visit(visit_data)

      if existing_visit
        Rails.logger.debug "Visit already exists: #{visit_data['name']}"
        next
      end

      # Create new visit
      begin
        visit_record = create_visit_record(visit_data)
        visits_created += 1
        Rails.logger.debug "Created visit: #{visit_record.name}"
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.error "Failed to create visit: #{e.message}"
        next
      end
    end

    Rails.logger.info "Visits import completed. Created: #{visits_created}"
    visits_created
  end

  private

  attr_reader :user, :visits_data

  def find_existing_visit(visit_data)
    user.visits.find_by(
      name: visit_data['name'],
      started_at: visit_data['started_at'],
      ended_at: visit_data['ended_at']
    )
  end

  def create_visit_record(visit_data)
    visit_attributes = prepare_visit_attributes(visit_data)
    user.visits.create!(visit_attributes)
  end

  def prepare_visit_attributes(visit_data)
    attributes = visit_data.except('place_reference')

    # Find and assign place if referenced
    if visit_data['place_reference']
      place = find_referenced_place(visit_data['place_reference'])
      attributes[:place] = place if place
    end

    attributes
  end

  def find_referenced_place(place_reference)
    return nil unless place_reference.is_a?(Hash)

    name = place_reference['name']
    latitude = place_reference['latitude'].to_f
    longitude = place_reference['longitude'].to_f

    # Find place by name and coordinates (global search since places are not user-specific)
    place = Place.find_by(name: name) ||
            Place.where("latitude = ? AND longitude = ?", latitude, longitude).first

    if place
      Rails.logger.debug "Found referenced place: #{name}"
    else
      Rails.logger.warn "Referenced place not found: #{name} (#{latitude}, #{longitude})"
    end

    place
  end
end
