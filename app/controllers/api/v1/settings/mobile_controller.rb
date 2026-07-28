# frozen_string_literal: true

class Api::V1::Settings::MobileController < ApiController
  before_action :authenticate_active_api_user!, only: %i[update]

  TRACKING_MODES = %w[precise significant].freeze
  BOOLEAN_KEYS = %w[
    tracking_visits track_visits_independently auto_start
    show_background_location_indicator upload_automatically
    upload_all_on_tracking_stop
  ].freeze
  NUMERIC_CLAMPS = {
    'distance_filter' => (1..10_000),
    'time_filter' => (1..3600),
    'track_break' => (1..1440),
    'accuracy' => (1..6),
    'batch_size' => (1..1000)
  }.freeze

  def show
    render json: mobile_settings_response, status: :ok
  end

  def update
    sanitized = sanitized_params
    settings = current_api_user.settings || {}
    existing = settings['mobile'] || {}
    settings['mobile'] = existing
                         .merge(sanitized)
                         .merge('updated_at' => Time.current.iso8601)

    if current_api_user.update(settings: settings)
      Rails.logger.info(
        "Mobile settings updated for user #{current_api_user.id}: #{sanitized.keys.join(', ')}"
      )
      render json: mobile_settings_response.merge(message: 'Settings updated'), status: :ok
    else
      render json: {
        message: 'Something went wrong',
        errors: current_api_user.errors.full_messages
      }, status: :unprocessable_content
    end
  end

  private

  def mobile_settings_response
    mobile = current_api_user.settings&.fetch('mobile', nil) || {}

    {
      settings: mobile.except('updated_at'),
      updated_at: mobile['updated_at'],
      status: 'success'
    }
  end

  def mobile_params
    params.require(:settings).permit(
      :tracking_mode, :tracking_visits, :track_visits_independently,
      :auto_start, :distance_filter, :time_filter, :track_break,
      :accuracy, :show_background_location_indicator,
      :upload_automatically, :upload_all_on_tracking_stop, :batch_size
    )
  end

  def sanitized_params
    sanitized = mobile_params.to_h

    sanitized.delete('tracking_mode') unless TRACKING_MODES.include?(sanitized['tracking_mode'])

    NUMERIC_CLAMPS.each do |key, range|
      next unless sanitized.key?(key)

      if sanitized[key].to_s.strip.empty?
        sanitized.delete(key)
      else
        sanitized[key] = sanitized[key].to_i.clamp(range.min, range.max)
      end
    end

    BOOLEAN_KEYS.each do |key|
      next unless sanitized.key?(key)

      if sanitized[key].to_s.strip.empty?
        sanitized.delete(key)
      else
        sanitized[key] = ActiveModel::Type::Boolean.new.cast(sanitized[key])
      end
    end

    sanitized
  end
end
