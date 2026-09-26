# frozen_string_literal: true

class AchievementsController < ApplicationController
  ROWS_PER_PAGE = 12

  before_action :authenticate_user!
  before_action :load_exploration, only: %i[index show]

  def index
    @sets = @continents
    mark_celebrated(@continents + @orphans)
  end

  def show
    definition = Achievements::Registry.find(params[:key])
    raise ActiveRecord::RecordNotFound if definition.nil?
    # World tiers are awarded in the background but have no UI entry point.
    return redirect_to achievements_path if definition.kind == 'region_set'
    raise ActiveRecord::RecordNotFound if definition.flat? && definition.parent_key.nil?
    return redirect_to achievement_path(definition.parent_key) if definition.flat?

    @set = presenters_for([definition]).first
    @sidebar_key = definition.parent_key || definition.key
    @query = params[:q].to_s.strip.first(100)
    @filter_status = params[:status].presence_in(%w[all unlocked in_progress locked]) || 'all'
    @children = paginate(attach_sharing(filtered_cards(@set.region_cards)))
    attach_silhouettes(@children)
    @threshold_minutes = current_user.safe_settings.min_minutes_spent_in_city

    mark_celebrated([@set])
  end

  def toggle_sharing
    raise ActiveRecord::RecordNotFound unless Achievements::Registry.find(params[:key])

    progress = sharing_carrier(params[:key])
    progress.with_lock do
      progress.update!(
        sharing_enabled: desired_sharing_state(progress),
        sharing_uuid: progress.sharing_uuid || SecureRandom.uuid
      )
    end

    respond_to do |format|
      format.html { redirect_back fallback_location: achievement_path(params[:key]) }
      format.json do
        render json: {
          enabled: progress.sharing_enabled,
          uuid: progress.sharing_uuid,
          url: progress.sharing_enabled ? shared_achievement_url(progress.sharing_uuid) : nil
        }
      end
    end
  end

  private

  def sharing_carrier(key)
    current_user.achievement_progresses.find_or_create_by!(achievement_key: key)
  rescue ActiveRecord::RecordNotUnique
    current_user.achievement_progresses.find_by!(achievement_key: key)
  end

  def load_exploration
    @exploration = Achievements::Progress.exploration_for(current_user)
    @state = @exploration.state
    @carriers = current_user.achievement_progresses
                            .where.not(achievement_key: Achievements::Progress::EXPLORATION_KEY)
                            .index_by(&:achievement_key)

    by_kind = Achievements::Registry.all.group_by(&:kind)
    @continents = presenters_for(by_kind.fetch('continent', []))
    @orphans = presenters_for(by_kind.fetch('country', []).select { |set| set.parent_key.nil? })
    @summary = Achievements::SummaryPresenter.new(state: @state)
  end

  def presenters_for(definitions)
    definitions.map do |definition|
      Achievements::SetPresenter.new(
        definition: definition, state: @state, sharing: @carriers[definition.key],
        timezone: current_user.safe_settings.timezone
      )
    end
  end

  def paginate(collection)
    Kaminari.paginate_array(collection).page(params[:page]).per(ROWS_PER_PAGE)
  end

  # Search the full collection before pagination; hydrate only visible geometry.
  def filtered_cards(cards)
    query = I18n.transliterate(@query).downcase
    cards.select do |card|
      matches_query = query.blank? || I18n.transliterate(card[:name]).downcase.include?(query)
      matches_status = case @filter_status
                       when 'unlocked' then card[:completed]
                       when 'in_progress' then !card[:locked] && !card[:completed]
                       when 'locked' then card[:locked]
                       else true
                       end
      matches_query && matches_status
    end
  end

  # Only the current page needs geometry. All states share the same SVG art;
  # no raster map request or per-card map instance is needed.
  def attach_silhouettes(cards)
    visible = cards.select { |card| card[:code] }
    return if visible.empty?

    shapes = Achievements::RegionSilhouettes.new(
      level: @set.level, codes: visible.map { |card| card[:code] }
    ).call
    visible.each do |card|
      card[:silhouette] = shapes[card[:code]]
      card[:geography_key] = @set.level == :country ? "country_#{card[:code].downcase}" : card[:code]
    end
  end

  # A leaf country card carries its own achievement key, so resolve that key's
  # current sharing state for the fullscreen Share/Embed controls.
  def attach_sharing(cards)
    cards.map do |card|
      next card unless card[:share_key]

      carrier = @carriers[card[:share_key]]
      card.merge(share: { key: card[:share_key],
                          shared: carrier&.sharing_enabled || false,
                          uuid: carrier&.sharing_uuid })
    end
  end

  # Deliberate write-on-GET: the celebration animation must fire exactly once,
  # on the first render that shows the completed card, so the page view itself
  # is the event being recorded.
  def mark_celebrated(sets)
    keys = sets.select(&:celebrate?).map { |set| set.definition.key }
    return if keys.empty? || !@exploration.persisted?

    @exploration.with_lock do
      celebrated = @exploration.state.fetch('celebrated', {})
      keys.each { |key| celebrated[key] = Time.current.iso8601 }
      @exploration.update!(state: @exploration.state.merge('celebrated' => celebrated))
    end
  end

  # An explicit `enabled` param sets sharing to that state (idempotent, so a
  # stale client can't flip the wrong way); absent, it falls back to a toggle.
  def desired_sharing_state(progress)
    return ActiveModel::Type::Boolean.new.cast(params[:enabled]) if params.key?(:enabled)

    !progress.sharing_enabled
  end
end
