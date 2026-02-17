# frozen_string_literal: true

class Api::V1::DigestsController < ApiController
  before_action :authenticate_active_api_user!, only: %i[create destroy]

  def index
    digests = current_api_user.digests.yearly.order(year: :desc)
    available_years = available_years_for_generation

    render json: Api::DigestListSerializer.new(digests: digests, available_years: available_years).call
  end

  def show
    digest = current_api_user.digests.yearly.find_by!(year: params[:year])

    return unless stale?(last_modified: digest.updated_at.utc)

    expires_in 1.hour, public: false
    render json: Api::DigestDetailSerializer.new(digest, distance_unit: distance_unit).call
  end

  def create
    year = params[:year].to_i

    unless valid_year?(year)
      render json: { error: 'Invalid year' }, status: :unprocessable_entity
      return
    end

    if current_api_user.digests.yearly.exists?(year: year)
      render json: { error: 'Digest already exists' }, status: :conflict
      return
    end

    Users::Digests::CalculatingJob.perform_later(current_api_user.id, year)
    render json: { message: "Digest for #{year} is being generated" }, status: :accepted
  end

  def destroy
    digest = current_api_user.digests.yearly.find_by!(year: params[:year])
    digest.destroy!
    head :no_content
  end

  private

  def authenticate_active_api_user!
    return if current_api_user&.active_until&.future?

    render json: { error: 'User is not active' }, status: :unauthorized
  end

  def available_years_for_generation
    tracked_years = current_api_user.stats.select(:year).distinct.pluck(:year)
    existing_digests = current_api_user.digests.yearly.pluck(:year)

    (tracked_years - existing_digests - [Time.current.year]).sort.reverse
  end

  def valid_year?(year)
    return false if year < 1970 || year >= Time.current.year

    current_api_user.stats.exists?(year: year)
  end

  def distance_unit
    params[:distance_unit].presence || current_api_user.safe_settings.distance_unit || 'km'
  end
end
