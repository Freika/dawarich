class Api::V1::RoutePresetsController < ApiController
  before_action :set_route_preset, only: %i[update destroy]

  def index
    presets = RoutePreset.order(:name)

    render json: presets.map { |preset| serialize_preset(preset) }
  end

  def create
    route_preset = RoutePreset.new(route_preset_params)

    if route_preset.save
      render json: serialize_preset(route_preset), status: :created
    else
      render json: { error: route_preset.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end
  end

  def update
    if @route_preset.update(route_preset_params)
      render json: serialize_preset(@route_preset)
    else
      render json: { error: @route_preset.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end
  end

  def destroy
    @route_preset.destroy!
    render json: { ok: true }
  end

  private

  def set_route_preset
    @route_preset = RoutePreset.find(params[:id])
  end

  def route_preset_params
    params.permit(
      :name,
      :start_lat,
      :start_lng,
      :end_lat,
      :end_lng,
      via_points: %i[lat lng]
    )
  end

  def serialize_preset(preset)
    {
      id: preset.id,
      name: preset.name,
      start: point_hash(preset.start_lat, preset.start_lng),
      end: point_hash(preset.end_lat, preset.end_lng),
      vias: preset.via_points || [],
      saved_at: preset.updated_at&.iso8601
    }
  end

  def point_hash(lat, lng)
    return nil if lat.nil? || lng.nil?

    {
      lat: lat,
      lng: lng
    }
  end
end
