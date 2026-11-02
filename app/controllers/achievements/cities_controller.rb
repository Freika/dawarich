# frozen_string_literal: true

module Achievements
  class CitiesController < ApplicationController
    before_action :authenticate_user!
    before_action :ensure_achievements_enabled!

    def create
      dataset = Exploration::Geography.current
      raise ActiveRecord::RecordNotFound unless dataset

      city = Exploration::Territory.find_by!(dataset_id: dataset.id, kind: 'city', code: params[:territory_code])
      current_user.achievement_city_selections.find_or_create_by!(territory_code: city.code)
      redirect_to achievement_cards_path, status: :see_other
    end

    def update
      selection = current_user.achievement_city_selections.find(params[:id])
      selection.update!(share_mosaic: ActiveModel::Type::Boolean.new.cast(params[:share_mosaic]))
      redirect_to achievement_cards_path, status: :see_other
    end

    def destroy
      current_user.achievement_city_selections.find(params[:id]).destroy!
      redirect_to achievement_cards_path, status: :see_other
    end
  end
end
