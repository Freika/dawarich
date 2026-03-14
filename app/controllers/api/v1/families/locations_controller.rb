# frozen_string_literal: true

class Api::V1::Families::LocationsController < ApiController
  before_action :ensure_family_feature_enabled!
  before_action :ensure_user_in_family!

  def index
    family_locations = Families::Locations.new(current_api_user).call

    render json: {
      locations: family_locations,
      updated_at: Time.current.iso8601,
      sharing_enabled: current_api_user.family_sharing_enabled?
    }
  end

  def history
    start_at = params[:start_at]
    end_at = params[:end_at]

    if start_at.blank? || end_at.blank?
      return render json: { error: 'start_at and end_at are required' }, status: :bad_request
    end

    parsed_start = Time.zone.parse(start_at)
    parsed_end = Time.zone.parse(end_at)

    return render json: { error: 'Invalid date format' }, status: :bad_request if parsed_start.nil? || parsed_end.nil?

    members = Families::Locations.new(current_api_user).history(
      start_at: parsed_start,
      end_at: parsed_end
    )

    render json: { members: members }
  rescue ArgumentError
    render json: { error: 'Invalid date format' }, status: :bad_request
  end

  private

  def ensure_user_in_family!
    return if current_api_user&.in_family?

    render json: { error: 'User is not part of a family' }, status: :forbidden
  end
end
