# frozen_string_literal: true

module Achievements
  # Turns a durable unlock event into the same spectral card used in the
  # collection. Only the front card is hydrated with geometry at any moment.
  class UnlockCardPresenter
    Card = Data.define(:attributes, :path, :name)

    def initialize(event:, state:, timezone: 'UTC')
      @event = event
      @state = state
      @timezone = timezone
    end

    def call
      return set_card if @event.kind == 'set'
      return country_card if @event.key.match?(/\A[A-Z]{2}\z/)

      subdivision_card
    end

    private

    def set_card
      definition = Registry.find(@event.key)
      return unless definition && definition.kind != 'region_set'

      presenter = SetPresenter.new(definition: definition, state: @state, timezone: @timezone)
      Card.new(attributes: presenter.card_attributes, path: achievement_path(definition.key), name: presenter.name)
    end

    def country_card
      definition = Registry.find("country_#{@event.key.downcase}")
      return unless definition

      presenter = SetPresenter.new(definition: definition, state: @state, timezone: @timezone)
      attributes = presenter.card_attributes
      if !definition.flat? && !presenter.completed?
        attributes = attributes.merge(name: definition.card['place'], description: nil, locked: false,
                                      earned_label: I18n.t('achievements.cards.status.visited'))
      end
      destination = definition.flat? ? definition.parent_key : definition.key
      path = if destination.nil?
               Rails.application.routes.url_helpers.achievements_path
             elsif definition.flat?
               achievement_path(destination, q: definition.card['place'], anchor: 'collection')
             else
               achievement_path(destination)
             end
      Card.new(attributes: attributes, path: path, name: attributes[:name])
    end

    def subdivision_card
      definition = Registry.subdivision_parent_for(@event.key)
      return unless definition

      name = definition.regions.fetch(@event.key)
      art = definition.card['art']
      silhouette = RegionSilhouettes.new(level: :subdivision, codes: [@event.key]).call[@event.key]
      attributes = {
        name: name,
        rarity: definition.card.fetch('rarities', {}).fetch(@event.key, 'Common'),
        map_lat: art['lat'], map_lon: art['lon'], map_zoom: art['zoom'],
        percent: 100, completed: true, locked: false,
        earned_label: I18n.t('achievements.cards.status.unlocked_on', date: unlocked_date),
        geography_key: @event.key, silhouette: silhouette
      }
      Card.new(attributes: attributes,
               path: achievement_path(definition.key, q: name, anchor: 'collection'), name: name)
    end

    def unlocked_date
      local_date = @event.created_at.in_time_zone(@timezone).to_date
      I18n.l(local_date, format: I18n.t('achievements.cards.date_format'))
    end

    def achievement_path(*args)
      Rails.application.routes.url_helpers.achievement_path(*args)
    end
  end
end
