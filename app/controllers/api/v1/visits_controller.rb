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
    visit = current_api_user.scoped_visits.find(params[:id])
    render json: Api::VisitSerializer.new(visit).call
  end

  def create
    service = Visits::Create.new(current_api_user, visit_params)

    result = service.call

    if result
      render json: Api::VisitSerializer.new(service.visit).call
    else
      error_message = service.errors || I18n.t('controllers.api.v1.visits.failed_to_create_visit')
      render json: { error: error_message }, status: :unprocessable_content
    end
  end

  def update
    visit = current_api_user.scoped_visits.find(params[:id])

    if visit_params[:place_id].present?
      place = current_api_user.places.find_by(id: visit_params[:place_id]) ||
              visit.suggested_places.find_by(id: visit_params[:place_id])
      if place.nil?
        return render json: { error: I18n.t('controllers.api.v1.visits.invalid_place') },
                      status: :unprocessable_content
      end
    end

    area = nil
    if visit_params[:area_id].present?
      area = current_api_user.areas.find_by(id: visit_params[:area_id])
      if area.nil?
        return render json: { error: I18n.t('controllers.api.v1.visits.invalid_area') },
                      status: :unprocessable_content
      end
    end

    visit = update_visit(visit, area: area)

    render json: Api::VisitSerializer.new(visit).call
  end

  def merge
    # Validate that we have at least 2 visit IDs
    visit_ids = params[:visit_ids]
    if visit_ids.blank? || visit_ids.length < 2
      return render json: { error: I18n.t('controllers.api.v1.visits.at_least_2_visits_must_be_selected_for_merging') },
                    status: :unprocessable_content
    end

    # Find all visits that belong to the current user
    visits = current_api_user.scoped_visits.where(id: visit_ids).order(started_at: :asc)

    # Ensure we found all the visits
    if visits.length != visit_ids.length
      return render json: { error: I18n.t('controllers.api.v1.visits.one_or_more_visits_not_found') },
                    status: :not_found
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
        message: I18n.t('controllers.api.v1.visits.count_visits_updated_successfully', count: result[:count]),
        updated_count: result[:count]
      }, status: :ok
    else
      render json: { error: service.errors.join(', ') }, status: :unprocessable_content
    end
  end

  def destroy
    visit = current_api_user.scoped_visits.find(params[:id])

    # Soft delete keeps the row as a tombstone so visit detection never
    # re-suggests it. Same contract as before: 204, points untouched.
    if visit.update(deleted_at: Time.current)
      head :no_content
    else
      render json: {
        error: I18n.t('controllers.api.v1.visits.failed_to_delete_visit'),
        errors: visit.errors.full_messages
      }, status: :unprocessable_content
    end
  rescue ActiveRecord::RecordNotFound
    render json: { error: I18n.t('controllers.api.v1.visits.visit_not_found') }, status: :not_found
  end

  private

  def visit_params
    params.require(:visit).permit(:name, :place_id, :area_id, :status, :latitude, :longitude, :started_at, :ended_at)
  end

  def merge_params
    params.permit(visit_ids: [])
  end

  def bulk_update_params
    params.permit(:status, visit_ids: [])
  end

  def update_visit(visit, area: nil)
    attributes = visit_params.to_h.except('latitude', 'longitude')
    user_provided_name = attributes['name'].present?

    visit.assign_attributes(attributes)

    if attributes['place_id'].present? && !user_provided_name && visit.place.present?
      visit.name = visit.place.name
    elsif area && !user_provided_name && area.name.present?
      visit.name = area.name
    end

    visit.save!

    visit
  end
end
