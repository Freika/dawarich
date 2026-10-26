# frozen_string_literal: true

class Api::V1::Traccar::PointsController < ApiController
  before_action :authenticate_active_api_user!, only: %i[create]
  before_action :validate_points_limit, only: %i[create]

  def create
    return render json: [], status: :ok if heartbeat?

    result = Traccar::PointCreator.new(point_params, current_api_user.id).call

    if result.blank?
      Rails.logger.warn('Traccar point rejected: unsupported or invalid payload')

      return render json: { error: I18n.t('controllers.api.v1.traccar.points.point_creation_failed') },
                    status: :unprocessable_content
    end

    render json: [], status: :ok
  rescue ActiveRecord::RecordInvalid, ActiveRecord::StatementInvalid, ArgumentError => e
    Rails.logger.error("Point creation failed: #{e.class}: #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)

    render json: { error: I18n.t('controllers.api.v1.traccar.points.point_creation_failed') },
           status: :internal_server_error
  end

  private

  COORDINATE_KEYS = %w[location lat lon lng latitude longitude coords].freeze

  def heartbeat?
    params[:id].present? && COORDINATE_KEYS.none? { |key| params.key?(key) }
  end

  def point_params
    params.permit(
      :device_id, :id, :lat, :lon, :timestamp, :accuracy, :altitude, :speed, :bearing, :batt, :charge, :alarm,
      location: [
        :timestamp, :latitude, :longitude, :accuracy, :speed, :heading, :altitude,
        :is_moving, :odometer, :event, :manual,
        { coords: %i[latitude longitude accuracy speed heading altitude],
          battery: %i[level is_charging],
          activity: %i[type] }
      ],
      battery: %i[level is_charging],
      activity: %i[type]
    )
  end
end
