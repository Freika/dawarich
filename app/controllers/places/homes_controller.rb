# frozen_string_literal: true

module Places
  # The Home periods of one Place, edited inside the `place_homes` Turbo Frame of the Place edit page.
  class HomesController < ApplicationController
    before_action :authenticate_user!
    before_action :set_place

    def create
      home = current_user.homes.build(home_params.merge(place: @place))
      return render_homes(home) unless home.save

      @place.adopt!
      redirect_to_edit
    end

    def update
      home = @place.homes.find(params[:id])
      return render_homes(home) unless home.update(home_params)

      redirect_to_edit
    end

    def destroy
      @place.homes.find(params[:id]).destroy!
      redirect_to_edit
    end

    private

    def set_place
      @place = current_user.places.find(params[:place_id])
    end

    def home_params
      params.require(:home).permit(:started_on, :ended_on)
    end

    def redirect_to_edit
      redirect_to edit_place_path(@place), status: :see_other
    end

    def render_homes(failed_home)
      render partial: 'places/homes', locals: { place: @place, failed_home: }, status: :unprocessable_content
    end
  end
end
