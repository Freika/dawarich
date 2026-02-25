# frozen_string_literal: true

class Users::DigestsController < ApplicationController
  helper Users::DigestsHelper
  helper CountryFlagHelper

  before_action :authenticate_user!
  before_action :authenticate_active_user!, only: [:create]
  before_action :set_digest, only: %i[show destroy]

  def index
    @digests = current_user.digests.yearly.order(year: :desc)
    @available_years = available_years_for_generation
  end

  def show
    @distance_unit = current_user.safe_settings.distance_unit || 'km'
  end

  def create
    year = params[:year].to_i

    if valid_year?(year)
      Users::Digests::CalculatingJob.perform_later(current_user.id, year)
      redirect_to users_digests_path,
                  notice: "Year-end digest for #{year} is being generated. Check back soon!",
                  status: :see_other
    else
      redirect_to users_digests_path, alert: 'Invalid year selected', status: :see_other
    end
  end

  def destroy
    year = @digest.year
    @digest.destroy!
    redirect_to users_digests_path, notice: "Year-end digest for #{year} has been deleted", status: :see_other
  end

  private

  def set_digest
    @digest = current_user.digests.yearly.find_by!(year: params[:year])
  rescue ActiveRecord::RecordNotFound
    redirect_to users_digests_path, alert: 'Digest not found'
  end

  def available_years_for_generation
    tracked_years = current_user.stats.select(:year).distinct.pluck(:year)
    existing_digests = current_user.digests.yearly.pluck(:year)

    (tracked_years - existing_digests - [Time.current.year]).sort.reverse
  end

  def valid_year?(year)
    return false if year < 1970 || year > Time.current.year

    current_user.stats.exists?(year: year)
  end
end
