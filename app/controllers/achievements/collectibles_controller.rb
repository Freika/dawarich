# frozen_string_literal: true

module Achievements
  class CollectiblesController < ApplicationController
    before_action :authenticate_user!
    before_action :ensure_achievements_enabled!

    def index
      @state = CollectionSchedule.call(current_user)
      @series = Collectible::SERIES.include?(params[:series]) ? params[:series] : nil
      @cards = current_user.achievement_collectibles.visible.includes(:city_selection, selection: :place).order(
        :series, :id
      )
      @cards = @cards.where(series: @series) if @series
      @cards = @cards.page(params[:page]).per(24)
      @query = params[:q].to_s.strip.first(100)
      @places = current_user.places.not_archived.ordered
      @places = @places.where('name ILIKE ?', "%#{Place.sanitize_sql_like(@query)}%") if @query.present?
      @places = @places.limit(30)
      @selections = current_user.achievement_selections.includes(:place).order(:id)
      dataset = Exploration::Geography.current
      @cities = dataset ? Exploration::Territory.where(dataset_id: dataset.id, kind: 'city').order(:name) : []
      @city_selections = current_user.achievement_city_selections.to_a
      Exploration::InstallGeographyJob.schedule unless dataset
    end

    def show
      @state = CollectionSchedule.call(current_user)
      @card = current_user.achievement_collectibles.visible.find(params[:id])
      @set = CollectiblePresenter.new(@card)
    end

    def toggle_sharing
      card = current_user.achievement_collectibles.visible.find(params[:id])
      state = CollectionState.find_by(user: current_user)
      return head :unprocessable_entity unless card.publishable? && state&.shareable?

      card.with_lock do
        enabled = params.key?(:enabled) ? ActiveModel::Type::Boolean.new.cast(params[:enabled]) : !card.sharing_enabled
        card.update!(sharing_enabled: enabled, sharing_uuid: card.sharing_uuid || SecureRandom.uuid)
      end
      respond_to do |format|
        format.html { redirect_to achievement_card_path(card), status: :see_other }
        format.json do
          render json: { enabled: card.sharing_enabled, uuid: card.sharing_uuid,
                         url: card.sharing_enabled ? shared_collectible_url(card.sharing_uuid) : nil }
        end
      end
    end
  end
end
