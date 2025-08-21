# frozen_string_literal: true

class Api::V1::VisitsController < ApiController
  def index
    visits = Visits::Finder.new(current_api_user, params).call
    serialized_visits = visits.map do |visit|
      Api::VisitSerializer.new(visit).call
    end

    render json: serialized_visits
  end

  def create
    visit = current_api_user.visits.build(visit_params.except(:latitude, :longitude))

    # If coordinates are provided but no place_id, create a place
    if visit_params[:latitude].present? && visit_params[:longitude].present? && visit.place_id.blank?
      place = create_place_from_coordinates(visit_params[:latitude], visit_params[:longitude], visit_params[:name])
      if place
        visit.place = place
      else
        return render json: { error: 'Failed to create place for visit' }, status: :unprocessable_entity
      end
    end

    # Validate that visit has a place
    if visit.place.blank?
      return render json: { error: 'Visit must have a valid place' }, status: :unprocessable_entity
    end

    # Set visit times and calculate duration
    visit.started_at = DateTime.parse(visit_params[:started_at])
    visit.ended_at = DateTime.parse(visit_params[:ended_at])
    visit.duration = (visit.ended_at - visit.started_at) * 24 * 60 # duration in minutes
    
    # Set status to confirmed for manually created visits
    visit.status = :confirmed

    visit.save!

    render json: Api::VisitSerializer.new(visit).call
  end

  def update
    visit = current_api_user.visits.find(params[:id])
    visit = update_visit(visit)

    render json: Api::VisitSerializer.new(visit).call
  end

  def merge
    # Validate that we have at least 2 visit IDs
    visit_ids = params[:visit_ids]
    if visit_ids.blank? || visit_ids.length < 2
      return render json: { error: 'At least 2 visits must be selected for merging' }, status: :unprocessable_entity
    end

    # Find all visits that belong to the current user
    visits = current_api_user.visits.where(id: visit_ids).order(started_at: :asc)

    # Ensure we found all the visits
    if visits.length != visit_ids.length
      return render json: { error: 'One or more visits not found' }, status: :not_found
    end

    # Use the service to merge the visits
    service = Visits::MergeService.new(visits)
    merged_visit = service.call

    if merged_visit&.persisted?
      render json: Api::VisitSerializer.new(merged_visit).call, status: :ok
    else
      render json: { error: service.errors.join(', ') }, status: :unprocessable_entity
    end
  end

  def bulk_update
    service = Visits::BulkUpdate.new(
      current_api_user,
      params[:visit_ids],
      params[:status]
    )

    result = service.call

    if result
      render json: {
        message: "#{result[:count]} visits updated successfully",
        updated_count: result[:count]
      }, status: :ok
    else
      render json: { error: service.errors.join(', ') }, status: :unprocessable_entity
    end
  end

  private

  def visit_params
    params.require(:visit).permit(:name, :place_id, :status, :latitude, :longitude, :started_at, :ended_at)
  end

  def merge_params
    params.permit(visit_ids: [])
  end

  def bulk_update_params
    params.permit(:status, visit_ids: [])
  end

  def create_place_from_coordinates(latitude, longitude, name)
    Rails.logger.info "Creating place from coordinates: lat=#{latitude}, lon=#{longitude}, name=#{name}"
    
    # Create a place at the specified coordinates
    place_name = name.presence || Place::DEFAULT_NAME

    # Validate coordinates
    lat_f = latitude.to_f
    lon_f = longitude.to_f
    
    if lat_f.abs > 90 || lon_f.abs > 180
      Rails.logger.error "Invalid coordinates: lat=#{lat_f}, lon=#{lon_f}"
      return nil
    end

    # Check if a place already exists very close to these coordinates (within 10 meters)
    existing_place = Place.joins("JOIN visits ON places.id = visits.place_id")
                          .where(visits: { user: current_api_user })
                          .where(
                            "ST_DWithin(lonlat, ST_SetSRID(ST_MakePoint(?, ?), 4326), ?)",
                            lon_f, lat_f, 0.0001 # approximately 10 meters
                          ).first

    if existing_place
      Rails.logger.info "Found existing place: #{existing_place.id}"
      return existing_place
    end

    # Create new place with both coordinate formats
    place = Place.create!(
      name: place_name,
      latitude: lat_f,
      longitude: lon_f,
      lonlat: "POINT(#{lon_f} #{lat_f})",
      source: :manual
    )
    
    Rails.logger.info "Created new place: #{place.id} at #{place.lonlat}"
    place
  rescue StandardError => e
    Rails.logger.error "Failed to create place: #{e.class} - #{e.message}"
    Rails.logger.error e.backtrace.join("\n") if Rails.env.development?
    nil
  end

  def update_visit(visit)
    visit_params.each do |key, value|
      next if %w[latitude longitude].include?(key.to_s)

      visit[key] = value
      visit.name = visit.place.name if visit_params[:place_id].present?
    end

    visit.save!

    visit
  end
end
