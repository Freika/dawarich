# frozen_string_literal: true

module Achievements
  class SelectionsController < ApplicationController
    before_action :authenticate_user!
    before_action :ensure_achievements_enabled!

    def create
      place = current_user.places.find(params[:place_id])
      current_user.achievement_selections.find_or_create_by!(place: place)
      redirect_to achievement_cards_path, status: :see_other
    end

    def update
      selection = current_user.achievement_selections.find(params[:id])
      selection.update!(timezone: params.require(:timezone), timezone_source: 'manual',
                        timezone_latitude: selection.place.lat, timezone_longitude: selection.place.lon)
      redirect_to achievement_cards_path, status: :see_other
    rescue ActiveRecord::RecordInvalid => e
      redirect_to achievement_cards_path, alert: e.record.errors.full_messages.to_sentence, status: :see_other
    end

    def destroy
      current_user.achievement_selections.find(params[:id]).destroy!
      redirect_to achievement_cards_path, status: :see_other
    end
  end
end
