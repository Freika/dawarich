# frozen_string_literal: true

class Api::V1::AchievementsController < ApiController
  def index
    render json: collection.overview
  end

  def show
    definition = visible_definition
    page = params[:page].presence || '1'
    unless page.to_s.match?(/\A[1-9]\d{0,8}\z/) &&
           (params[:status].blank? || %w[all unlocked in_progress locked].include?(params[:status]))
      return render json: { error: 'invalid_parameters' }, status: :unprocessable_content
    end

    render json: collection.detail(definition, query: params[:q].to_s.strip.first(100),
                                   status: params[:status].presence || 'all', page: page.to_i)
  end

  def sharing
    definition = visible_definition
    unless [true, false].include?(params[:enabled])
      return render json: { error: 'enabled_must_be_boolean' }, status: :unprocessable_content
    end

    progress = sharing_carrier(definition.key)
    progress.with_lock do
      progress.update!(sharing_enabled: params[:enabled],
                       sharing_uuid: progress.sharing_uuid || SecureRandom.uuid)
    end
    render json: { enabled: progress.sharing_enabled, uuid: progress.sharing_uuid,
                   url: progress.sharing_enabled ? shared_achievement_url(progress.sharing_uuid) : nil }
  end

  private

  def collection
    @collection ||= ::Achievements::ApiCollection.new(user: current_api_user, url_helpers: self)
  end

  def visible_definition
    definition = ::Achievements::Registry.find(params[:key])
    raise ActiveRecord::RecordNotFound unless definition && definition.kind != 'region_set'

    definition
  end

  def sharing_carrier(key)
    current_api_user.achievement_progresses.find_or_create_by!(achievement_key: key)
  rescue ActiveRecord::RecordNotUnique
    current_api_user.achievement_progresses.find_by!(achievement_key: key)
  end
end
