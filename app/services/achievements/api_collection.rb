# frozen_string_literal: true

module Achievements
  # JSON representation of the server-authoritative collection. Geometry is
  # loaded after filtering and pagination, rather than for the entire atlas.
  class ApiCollection
    PER_PAGE = 12

    def initialize(user:, url_helpers:)
      @user = user
      @url_helpers = url_helpers
      @state = Progress.exploration_for(user).state || {}
      @sharing = user.achievement_progresses.where.not(achievement_key: Progress::EXPLORATION_KEY)
                     .index_by(&:achievement_key)
    end

    def overview
      summary = SummaryPresenter.new(state: @state)
      definitions = Registry.all.select do |definition|
        definition.kind == 'continent' || (definition.kind == 'country' && definition.parent_key.nil?)
      end
      {
        summary: %i[earned_countries total_countries earned_subdivisions total_subdivisions percent]
                 .index_with { |key| summary.public_send(key) },
        collections: definitions.map { |definition| card(definition, geometry: true) },
        threshold_minutes: threshold_minutes
      }
    end

    def detail(definition, query:, status:, page:)
      children = if definition.flat?
                   []
                 elsif definition.level == :subdivision
                   definition.regions.map { |code, name| subdivision(definition, code, name) }
                 else
                   definition.region_codes.filter_map do |code|
                     child = Registry.find("country_#{code.downcase}")
                     card(child) if child
                   end
                 end
      normalized = I18n.transliterate(query).downcase
      children.select! do |child|
        matches = normalized.empty? || I18n.transliterate(child[:name]).downcase.include?(normalized)
        matches && case status
                   when 'unlocked' then child[:completed]
                   when 'in_progress' then !child[:locked] && !child[:completed]
                   when 'locked' then child[:locked]
                   else true
                   end
      end
      children.sort_by! { |child| [child[:locked] ? 1 : 0, child[:name]] }
      total = children.size
      visible = children.slice((page - 1) * PER_PAGE, PER_PAGE) || []
      shapes = RegionSilhouettes.new(level: definition.level, codes: visible.map { |child| child[:code] }).call
      visible.each { |child| child[:silhouette] = shapes[child[:code]] }
      {
        collection: card(definition, geometry: true), cards: visible,
        pagination: { current_page: page, total_pages: (total.to_f / PER_PAGE).ceil,
                      total_count: total, per_page: PER_PAGE }, threshold_minutes: threshold_minutes
      }
    end

    def unlock(event)
      presentation = UnlockCardPresenter.new(event: event, state: @state, timezone: @user.timezone).call
      return unless presentation

      result = if event.kind == 'set'
                 definition = Registry.find(event.key)
                 card(definition) if definition && definition.kind != 'region_set'
               elsif event.key.match?(/\A[A-Z]{2}\z/)
                 definition = Registry.find("country_#{event.key.downcase}")
                 card(definition) if definition
               else
                 definition = Registry.subdivision_parent_for(event.key)
                 subdivision(definition, event.key, definition.regions[event.key]) if definition
               end
      return unless result

      if result[:kind] == 'subdivision'
        # A durable geography event proves the award even if its progress row
        # has been rebuilt since the event was enqueued.
        result = result.merge(earned_count: 1, earned_at: result[:earned_at] || event.created_at.utc.iso8601)
      end
      result.merge(presentation.attributes.slice(:name, :description, :rarity, :percent, :completed, :locked,
                                                 :geography_key, :silhouette))
    end

    private

    def card(definition, geometry: false)
      presenter = SetPresenter.new(definition: definition, state: @state,
                                   sharing: @sharing[definition.key], timezone: @user.timezone)
      visited = definition.country && @state.dig('earned', definition.country)
      {
        key: definition.key, name: definition.kind == 'country' ? definition.card['place'] : presenter.name,
        kind: definition.kind, code: definition.country, parent_key: definition.parent_key,
        browse_key: definition.flat? ? nil : definition.key, share_key: definition.key,
        description: presenter.description, rarity: presenter.rarity, percent: presenter.percent,
        earned_count: presenter.earned_count, target: presenter.target, completed: presenter.completed?,
        locked: presenter.locked? && visited.blank?, earned_at: completion_time(presenter),
        geography_key: definition.key, silhouette: geometry ? presenter.card_attributes[:silhouette] : nil,
        sharing: sharing_state(definition.key)
      }
    end

    def subdivision(definition, code, name)
      earned_at = @state.dig('earned', code)
      {
        key: code, name: name, kind: 'subdivision', code: code, parent_key: definition.key,
        browse_key: nil, share_key: nil, description: nil,
        rarity: definition.card.fetch('rarities', {}).fetch(code, 'Common'),
        percent: earned_at.present? ? 100 : 0, earned_count: earned_at.present? ? 1 : 0,
        target: 1, completed: earned_at.present?, locked: earned_at.blank?, earned_at: earned_at,
        geography_key: code, silhouette: nil, sharing: { enabled: false, url: nil }
      }
    end

    def completion_time(presenter)
      return unless presenter.completed?

      presenter.earned.values.sort_by { |value| timestamp_sort_key(value) }[presenter.target - 1]
    end

    def timestamp_sort_key(value)
      Time.iso8601(value)
    rescue ArgumentError
      Date.parse(value).to_time
    end

    def sharing_state(key)
      carrier = @sharing[key]
      enabled = carrier&.sharing_enabled || false
      { enabled: enabled, url: enabled ? @url_helpers.shared_achievement_url(carrier.sharing_uuid) : nil }
    end

    def threshold_minutes
      @user.safe_settings.min_minutes_spent_in_city
    end
  end
end
