# frozen_string_literal: true

class Users::ImportData::Areas
  BATCH_SIZE = 1000

  def initialize(user, areas_data)
    @user = user
    @areas_data = areas_data
  end

  def call
    return 0 unless areas_data.is_a?(Array)

    Rails.logger.info "Importing #{areas_data.size} areas for user: #{user.email}"

    # Filter valid areas and prepare for bulk import
    valid_areas = filter_and_prepare_areas

    if valid_areas.empty?
      Rails.logger.info "Areas import completed. Created: 0"
      return 0
    end

    # Remove existing areas to avoid duplicates
    deduplicated_areas = filter_existing_areas(valid_areas)

    if deduplicated_areas.size < valid_areas.size
      Rails.logger.debug "Skipped #{valid_areas.size - deduplicated_areas.size} duplicate areas"
    end

    # Bulk import in batches
    total_created = bulk_import_areas(deduplicated_areas)

    Rails.logger.info "Areas import completed. Created: #{total_created}"
    total_created
  end

  private

  attr_reader :user, :areas_data

  def filter_and_prepare_areas
    valid_areas = []
    skipped_count = 0

    areas_data.each do |area_data|
      next unless area_data.is_a?(Hash)

      # Skip areas with missing required data
      unless valid_area_data?(area_data)
        skipped_count += 1
        next
      end

      # Prepare area attributes for bulk insert
      prepared_attributes = prepare_area_attributes(area_data)
      valid_areas << prepared_attributes if prepared_attributes
    end

    if skipped_count > 0
      Rails.logger.warn "Skipped #{skipped_count} areas with invalid or missing required data"
    end

    valid_areas
  end

  def prepare_area_attributes(area_data)
    # Start with base attributes, excluding timestamp fields
    attributes = area_data.except('created_at', 'updated_at')

    # Add required attributes for bulk insert
    attributes['user_id'] = user.id
    attributes['created_at'] = Time.current
    attributes['updated_at'] = Time.current

    # Ensure radius is present (required by model validation)
    attributes['radius'] ||= 100 # Default radius if not provided

    # Convert string keys to symbols for consistency
    attributes.symbolize_keys
  rescue StandardError => e
    Rails.logger.error "Failed to prepare area attributes: #{e.message}"
    Rails.logger.error "Area data: #{area_data.inspect}"
    nil
  end

  def filter_existing_areas(areas)
    return areas if areas.empty?

    # Build lookup hash of existing areas for this user
    existing_areas_lookup = {}
    user.areas.select(:name, :latitude, :longitude).each do |area|
      # Normalize decimal values for consistent comparison
      key = [area.name, area.latitude.to_f, area.longitude.to_f]
      existing_areas_lookup[key] = true
    end

    # Filter out areas that already exist
    filtered_areas = areas.reject do |area|
      # Normalize decimal values for consistent comparison
      key = [area[:name], area[:latitude].to_f, area[:longitude].to_f]
      if existing_areas_lookup[key]
        Rails.logger.debug "Area already exists: #{area[:name]}"
        true
      else
        false
      end
    end

    filtered_areas
  end

  def bulk_import_areas(areas)
    total_created = 0

    areas.each_slice(BATCH_SIZE) do |batch|
      begin
        # Use upsert_all to efficiently bulk insert areas
        result = Area.upsert_all(
          batch,
          returning: %w[id],
          on_duplicate: :skip
        )

        batch_created = result.count
        total_created += batch_created

        Rails.logger.debug "Processed batch of #{batch.size} areas, created #{batch_created}, total created: #{total_created}"

      rescue StandardError => e
        Rails.logger.error "Failed to process area batch: #{e.message}"
        Rails.logger.error "Batch size: #{batch.size}"
        Rails.logger.error "Backtrace: #{e.backtrace.first(3).join('\n')}"
        # Continue with next batch instead of failing completely
      end
    end

    total_created
  end

  def valid_area_data?(area_data)
    # Check for required fields
    return false unless area_data.is_a?(Hash)
    return false unless area_data['name'].present?
    return false unless area_data['latitude'].present?
    return false unless area_data['longitude'].present?

    true
  rescue StandardError => e
    Rails.logger.debug "Area validation failed: #{e.message} for data: #{area_data.inspect}"
    false
  end
end
