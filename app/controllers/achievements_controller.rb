# frozen_string_literal: true

class AchievementsController < ApplicationController
  ROWS_PER_PAGE = 10

  before_action :authenticate_user!
  before_action :require_feature_enabled
  before_action :load_exploration, only: %i[index show]

  def index
    @sets = @continents
    mark_celebrated(@continents + @orphans + @tiers)
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
    children = @set.compact? ? @set.region_rows : attach_sharing(@set.region_cards)
    @children = paginate(children)
    attach_silhouettes(@children) unless @set.compact?

    mark_celebrated([@set])
  end

  def toggle_sharing
    raise ActiveRecord::RecordNotFound unless Achievements::Registry.find(params[:key])

    progress = current_user.achievement_progresses.find_or_create_by!(achievement_key: params[:key])
    progress.update!(
      sharing_enabled: desired_sharing_state(progress),
      sharing_uuid: progress.sharing_uuid || SecureRandom.uuid
    )

    respond_to do |format|
      format.html { redirect_to achievements_path }
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

  def load_exploration
    @exploration = Achievements::Progress.exploration_for(current_user)
    @state = @exploration.state
    @carriers = current_user.achievement_progresses
                            .where.not(achievement_key: Achievements::Progress::EXPLORATION_KEY)
                            .index_by(&:achievement_key)

    by_kind = Achievements::Registry.all.group_by(&:kind)
    @continents = presenters_for(by_kind.fetch('continent', []))
    @tiers = presenters_for(by_kind.fetch('region_set', []))
    @orphans = presenters_for(by_kind.fetch('country', []).select { |set| set.parent_key.nil? })
    @summary = Achievements::SummaryPresenter.new(state: @state)
  end

  def presenters_for(definitions)
    definitions.map do |definition|
      Achievements::SetPresenter.new(
        definition: definition, state: @state, sharing: @carriers[definition.key]
      )
    end
  end

  def paginate(collection)
    Kaminari.paginate_array(collection).page(params[:page]).per(ROWS_PER_PAGE)
  end

  # Locked cards on the current page swap their map art for the region's
  # geometry outline. Mutates the paginated hashes in place so Kaminari's
  # pagination metadata survives.
  def attach_silhouettes(cards)
    locked = cards.select { |card| card[:locked] && card[:code] }
    return if locked.empty?

    shapes = Achievements::RegionSilhouettes.new(
      level: @set.level, codes: locked.map { |card| card[:code] }
    ).call
    locked.each { |card| card[:silhouette] = shapes[card[:code]] }
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

  def require_feature_enabled
    redirect_to root_path unless Flipper.enabled?(:achievements)
  end

  # An explicit `enabled` param sets sharing to that state (idempotent, so a
  # stale client can't flip the wrong way); absent, it falls back to a toggle.
  def desired_sharing_state(progress)
    return ActiveModel::Type::Boolean.new.cast(params[:enabled]) if params.key?(:enabled)

    !progress.sharing_enabled
  end
end
