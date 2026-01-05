# frozen_string_literal: true

class Api::V1::VisitsController < ApiController
  def index
    visits = Visits::Finder.new(current_api_user, params).call

    # Support optional pagination (backward compatible - returns all if no page param)
    if params[:page].present?
      per_page = [params[:per_page]&.to_i || 100, 500].min
      visits = visits.page(params[:page]).per(per_page)

      response.set_header('X-Current-Page', visits.current_page.to_s)
      response.set_header('X-Total-Pages', visits.total_pages.to_s)
      response.set_header('X-Total-Count', visits.total_count.to_s)
    end

    serialized_visits = visits.map do |visit|
      Api::VisitSerializer.new(visit).call
    end

    render json: serialized_visits
  end

  def show
    visit = current_api_user.visits.find(params[:id])
    render json: Api::VisitSerializer.new(visit).call
  end

  def create
    service = Visits::Create.new(current_api_user, visit_params)

    result = service.call

    if result
      render json: Api::VisitSerializer.new(service.visit).call
    else
      error_message = service.errors || 'Failed to create visit'
      render json: { error: error_message }, status: :unprocessable_content
    end
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
      return render json: { error: 'At least 2 visits must be selected for merging' }, status: :unprocessable_content
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
      render json: { error: service.errors.join(', ') }, status: :unprocessable_content
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
      render json: { error: service.errors.join(', ') }, status: :unprocessable_content
    end
  end

  def destroy
    visit = current_api_user.visits.find(params[:id])

    if visit.destroy
      head :no_content
    else
      render json: {
        error: 'Failed to delete visit',
        errors: visit.errors.full_messages
      }, status: :unprocessable_content
    end
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Visit not found' }, status: :not_found
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
