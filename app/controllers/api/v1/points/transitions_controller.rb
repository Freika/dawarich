# frozen_string_literal: true

class Api::V1::Points::TransitionsController < ApiController
  FUTURE_TOLERANCE = 5.minutes
  PAST_HORIZON = 24.hours
  MAX_ACCURACY_M = 100_000
  MAX_DEVICE_ID = 255
  MAX_METADATA_KEYS = 20
  MAX_METADATA_BYTES = 2_048
  SCALARS = [NilClass, String, Numeric, TrueClass, FalseClass].freeze

  before_action :authenticate_active_api_user!

  def create
    attributes = transition_attributes
    return head :unprocessable_content unless attributes

    place = current_api_user.places.monitored_geofences.find_by(id: params[:place_id])
    return head :no_content unless place

    GeofenceEvents::Record.call(user: current_api_user, place:, source: :native_app, **attributes,
                                apply_state: newer_than_evaluated?(attributes[:occurred_at]))
    head :created
  end

  private

  def transition_attributes
    event_type = params[:event_type].to_s
    occurred_at = parse_time(params[:occurred_at])
    lon, lat = coordinates
    return unless %w[enter leave].include?(event_type) && occurred_at && lon && valid_extras?

    { event_type:, occurred_at:, lonlat: "POINT(#{lon} #{lat})", accuracy_m: accuracy,
      device_id: params[:device_id].presence, metadata: }
  end

  def parse_time(value)
    time = Time.iso8601(value.to_s)
    time if time.between?(PAST_HORIZON.ago, FUTURE_TOLERANCE.from_now)
  rescue ArgumentError
    nil
  end

  def coordinates
    pair = Array(params[:lonlat])
    return unless pair.size == 2

    lon, lat = pair.map { |value| Float(value.to_s, exception: false) }
    [lon, lat] if lon&.between?(-180, 180) && lat&.between?(-90, 90)
  end

  def accuracy
    value = Float(params[:accuracy_m].to_s, exception: false)
    value.round if value&.between?(0, MAX_ACCURACY_M)
  end

  def valid_extras?
    params[:device_id].to_s.length <= MAX_DEVICE_ID && !metadata.nil?
  end

  def metadata
    return @metadata if defined?(@metadata)

    raw = params[:metadata].respond_to?(:to_unsafe_h) ? params[:metadata].to_unsafe_h : params[:metadata]
    @metadata = sanitized_metadata(raw || {})
  end

  def sanitized_metadata(raw)
    return unless raw.is_a?(Hash) && raw.size <= MAX_METADATA_KEYS
    return unless raw.values.all? { |value| SCALARS.any? { |type| value.is_a?(type) } }

    raw.to_h.stringify_keys if raw.to_json.bytesize <= MAX_METADATA_BYTES
  end

  def newer_than_evaluated?(occurred_at)
    evaluated_at = GeofenceEvents::StateStore.new(current_api_user).evaluated_at
    evaluated_at.nil? || occurred_at.to_i >= evaluated_at
  rescue GeofenceEvents::StateStore::Unavailable
    true
  end
end
