# frozen_string_literal: true

module Places
  # The Home periods of one Place, edited inside the `place_homes` Turbo Frame of the Place edit page
  # or added in one click from the Places list.
  class HomesController < ApplicationController
    before_action :authenticate_user!
    before_action :set_place

    def create
      home = current_user.homes.build(home_params.merge(place: @place))
      return render_homes(home) unless home.save

      @place.adopt!
      return redirect_to_edit unless params[:list]

      # "I live here" on the Places list: back to the same page of the list.
      redirect_back_or_to places_path, notice: I18n.t('trip_detection.onboarding.home_saved'), status: :see_other
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
