# frozen_string_literal: true

class Api::V1::Families::LocationRequestsController < ApiController
  before_action :ensure_family_feature_available!
  before_action :ensure_user_in_family!

  def create
    target = current_api_user.family.members.find_by(id: params[:target_user_id])

    unless target
      return render json: { error: I18n.t('controllers.family.location_requests.user_not_found_in_your_family') },
                    status: :not_found
    end

    result = Families::CreateLocationRequest.new(requester: current_api_user, target_user: target).call

    if result.success?
      request_record = result.payload[:request]
      render json: {
        request: {
          id: request_record.id,
          target_user_id: request_record.target_user_id,
          expires_at: request_record.expires_at.iso8601
        }
      }, status: :created
    else
      render json: result.payload, status: result.status
    end
  end

  def accept
    respond_to_request(:accept)
  end

  def decline
    respond_to_request(:decline)
  end

  private

  def respond_to_request(decision)
    request_record = Family::LocationRequest.where(family: current_api_user.family).find_by(id: params[:id])

    unless request_record
      return render json: { error: I18n.t('controllers.api.v1.families.location_requests.not_found') },
                    status: :not_found
    end

    result = Families::RespondToLocationRequest.new(
      request: request_record,
      responder: current_api_user,
      decision: decision,
      duration: params[:duration]
    ).call

    render json: result.payload, status: result.status
  end

  def ensure_user_in_family!
    return if current_api_user&.in_family?

    render json: { error: I18n.t('controllers.api.v1.families.locations.user_is_not_part_of_a_family') },
           status: :not_found
  end
end
