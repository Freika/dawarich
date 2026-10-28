# frozen_string_literal: true

class Shared::CollectiblesController < ApplicationController
  include DefaultDateTimePreferences

  before_action :find_card

  def show
    I18n.with_locale(@card.user.locale) do
      @embed = params[:embed] == '1'
      @set = Achievements::CollectiblePresenter.new(@card, public: true)
      render :show, layout: @embed ? 'achievement_embed' : 'shared'
    end
    response.headers.delete('X-Frame-Options')
    response.headers['Content-Security-Policy'] = 'frame-ancestors *'
    response.headers['Cache-Control'] = 'private, no-store'
  end

  def image
    response.headers['Cache-Control'] = 'private, no-store'
    I18n.with_locale(@card.user.locale) do
      send_data Achievements::OgImage.new(Achievements::CollectiblePresenter.new(@card, public: true)).call,
                type: 'image/png', disposition: 'inline'
    end
  end

  private

  def find_card
    @card = Achievements::Collectible.find_by!(sharing_uuid: params[:uuid], sharing_enabled: true, revoked_at: nil)
    valid = @card.user&.feature_enabled?(:achievements) && @card.publishable? &&
            Achievements::CollectionState.find_by(user_id: @card.user_id)&.current?
    raise ActiveRecord::RecordNotFound unless valid
  end
end
