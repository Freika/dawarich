# frozen_string_literal: true

class Api::V1::Families::LocationsController < Api::V1::Families::BaseController
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
      return render json: { error: I18n.t('controllers.api.v1.families.locations.start_at_and_end_at_are_required') },
                    status: :bad_request
    end

    parsed_start = Time.zone.parse(start_at)
    parsed_end = Time.zone.parse(end_at)

    if parsed_start.nil? || parsed_end.nil?
      return render json: { error: I18n.t('controllers.api.v1.families.locations.invalid_date_format') },
                    status: :bad_request
    end

    members = Families::Locations.new(current_api_user).history(
      start_at: parsed_start,
      end_at: parsed_end
    )

    render json: { members: members }
  rescue ArgumentError
    render json: { error: I18n.t('controllers.api.v1.families.locations.invalid_date_format') }, status: :bad_request
  end
end
