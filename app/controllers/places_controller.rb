# frozen_string_literal: true

class PlacesController < ApplicationController
  include FlashStreamable

  before_action :authenticate_user!
  before_action :set_place, only: %i[destroy update]

  def index
    @places = current_user.places.page(params[:page]).per(20)
  end

  def show
    @place = current_user.places.includes(:tags).find(params[:id])
    @visits = @place.visits.active.order(started_at: :desc).page(params[:page]).per(10)
  end

  def create
    @place = current_user.places.build(place_params.except(:tag_ids))
    @place.user_named = true

    if @place.save
      add_tags if tag_ids.present?
      @place = current_user.places.includes(:tags, :active_visits).find(@place.id)

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace('place-creation-data', html: place_data_element),
            stream_flash(:success, I18n.t('controllers.places.created'))
          ]
        end
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: stream_flash(:error, @place.errors.full_messages.join(', '))
        end
      end
    end
  end

  def update
    if @place.update(place_params.except(:tag_ids))
      @place.adopt!
      set_tags if params[:place]&.key?(:tag_ids)
      @place = current_user.places.includes(:tags, :active_visits).find(@place.id)

      respond_to do |format|
        format.json { render json: { name: @place.name }, status: :ok }
        format.turbo_stream do
          if drawer_request?
            recent_visits = @place.visits.active.order(started_at: :desc).limit(5)
            render turbo_stream: [
              turbo_stream.replace(
                'place-drawer',
                partial: 'places/drawer',
                locals: { place: @place, recent_visits: recent_visits }
              ),
              stream_flash(:success, I18n.t('controllers.places.updated'))
            ]
          else
            render turbo_stream: [
              turbo_stream.replace('place-creation-data', html: place_data_element(updated: true)),
              stream_flash(:success, I18n.t('controllers.places.updated'))
            ]
          end
        end
      end
    else
      respond_to do |format|
        format.json { render json: { error: @place.errors.full_messages.join(', ') }, status: :unprocessable_entity }
        format.turbo_stream do
          render turbo_stream: stream_flash(:error, @place.errors.full_messages.join(', '))
        end
      end
    end
  end

  def nearby
    return head :bad_request unless params[:latitude].present? && params[:longitude].present?

    radius = params[:radius]&.to_f || 0.5

    results = Places::NearbySearch.new(
      user: current_user,
      latitude: params[:latitude].to_f,
      longitude: params[:longitude].to_f,
      radius: radius,
      limit: params[:limit]&.to_i || 5
    ).call

    render partial: 'places/nearby_places', locals: {
      places: results, radius: radius, max_radius: 1.5
    }
  end

  def destroy
    @place.destroy!

    redirect_to places_url(page: params[:page]), notice: I18n.t('controllers.places.place_was_successfully_destroyed'),
status: :see_other
  end

  private

  def set_place
    @place = current_user.places.find(params[:id])
  end

  def drawer_request?
    request.headers['Turbo-Frame'] == 'place-drawer'
  end

  def place_params
    params.require(:place).permit(:name, :latitude, :longitude, :source, :note, tag_ids: [])
  end

  def tag_ids
    ids = params.dig(:place, :tag_ids)
    Array(ids).compact
  end

  def add_tags
    tags = current_user.tags.where(id: tag_ids)
    @place.tags << tags
  end

  def set_tags
    tag_ids_param = Array(params.dig(:place, :tag_ids)).compact
    tags = current_user.tags.where(id: tag_ids_param)
    @place.tags = tags
  end

  def place_data_element(updated: false)
    data = serialize_place(@place)
    helpers.tag.div(
      id: 'place-creation-data',
      data: { place: data.to_json, created: !updated, updated: updated },
      class: 'hidden'
    )
  end

  def serialize_place(place)
    {
      id: place.id, name: place.name, latitude: place.lat, longitude: place.lon,
      source: place.source, note: place.note, icon: place.tags.first&.icon,
      color: place.tags.first&.color, visits_count: place.active_visits.size,
      tags: place.tags.map { |t| { id: t.id, name: t.name, icon: t.icon, color: t.color } }
    }
  end
end
