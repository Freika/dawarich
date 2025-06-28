# frozen_string_literal: true

class Users::ImportData::Areas
  def initialize(user, areas_data)
    @user = user
    @areas_data = areas_data
  end

  def call
    return 0 unless areas_data.is_a?(Array)

    Rails.logger.info "Importing #{areas_data.size} areas for user: #{user.email}"

    areas_created = 0

    areas_data.each do |area_data|
      next unless area_data.is_a?(Hash)

      # Skip if area already exists (match by name and coordinates)
      existing_area = user.areas.find_by(
        name: area_data['name'],
        latitude: area_data['latitude'],
        longitude: area_data['longitude']
      )

      if existing_area
        Rails.logger.debug "Area already exists: #{area_data['name']}"
        next
      end

      # Create new area
      area_attributes = area_data.merge(user: user)
      # Ensure radius is present (required by model validation)
      area_attributes['radius'] ||= 100 # Default radius if not provided

      area = user.areas.create!(area_attributes)
      areas_created += 1

      Rails.logger.debug "Created area: #{area.name}"
    rescue ActiveRecord::RecordInvalid => e
      ExceptionReporter.call(e, "Failed to create area")

      next
    end

    Rails.logger.info "Areas import completed. Created: #{areas_created}"
    areas_created
  end

  private

  attr_reader :user, :areas_data
end
