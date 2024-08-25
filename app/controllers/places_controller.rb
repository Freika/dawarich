# frozen_string_literal: true

class PlacesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_place, only: :destroy

  def index
    @places = current_user.places.page(params[:page]).per(20)
  end

  def destroy
    @place.destroy!

    redirect_to places_url, notice: 'Place was successfully destroyed.', status: :see_other
  end

  private

  def set_place
    @place = current_user.places.find(params[:id])
  end
end
