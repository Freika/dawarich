# frozen_string_literal: true

module Achievements
  class SetPresenter
    DEFAULT_CHILD_ZOOM = 6

    attr_reader :definition, :state, :sharing

    def initialize(definition:, state: {}, sharing: nil)
      @definition = definition
      @state = state || {}
      @sharing = sharing
    end

    delegate :total, :target, :flat?, :level, :parent_key, to: :definition

    def compact?
      definition.kind == 'region_set'
    end

    def earned
      @earned ||= state.fetch('earned', {}).slice(*definition.region_codes)
    end

    def earned_count
      earned.size
    end

    def completed?
      earned_count >= target
    end

    def display_count
      [earned_count, target].min
    end

    def regions
      definition.regions
                .map { |code, name| { code: code, name: name, earned_at: earned[code] } }
                .sort_by { |region| region[:name] }
    end

    def sharing_enabled?
      sharing&.sharing_enabled || false
    end

    def sharing_uuid
      sharing&.sharing_uuid
    end

    def percent
      return 0 if target.zero?

      [(earned_count * 100.0 / target).round, 100].min
    end

    def locked?
      earned_count.zero?
    end

    def completed_on
      return nil unless completed?

      earned.values.map { |date| Date.parse(date) }.sort[target - 1]
    end

    def earned_label
      return 'Locked' if locked?
      return "Unlocked · #{completed_on.strftime('%-d %b %Y')}" if completed?

      # Absolute count, not a percent: the plate bar already shows how far,
      # so the label carries the number the bar can't.
      "#{display_count}/#{target} #{level == :country ? 'countries' : 'regions'}"
    end

    def celebrate?
      completed? && state.dig('celebrated', definition.key).blank?
    end

    def rarity
      definition.card['rarity']
    end

    def description
      definition.card['description']
    end

    def flavor
      definition.card['flavor']
    end

    def place
      definition.card['place']
    end

    def card_attributes
      art = definition.card['art']
      marker = definition.card['marker'] || art

      {
        name: definition.name,
        description: description,
        flavor: flavor,
        rarity: rarity,
        place: place,
        map_lat: art['lat'],
        map_lon: art['lon'],
        map_zoom: art['zoom'],
        marker_lat: marker['lat'],
        marker_lon: marker['lon'],
        percent: percent,
        completed: completed?,
        locked: locked?,
        earned_label: earned_label
      }
    end

    def region_cards
      cards = level == :subdivision ? subdivision_cards : country_cards

      cards.sort_by { |card| [card[:locked] ? 1 : 0, card[:name]] }
    end

    def region_rows
      definition.regions
                .map { |code, name| region_row(code, name) }
                .sort_by { |row| [row[:earned_at] ? 0 : 1, row[:name]] }
    end

    private

    def region_row(code, name)
      child = level == :country ? Registry.find("country_#{code.downcase}") : nil

      {
        code: code,
        name: child ? child.card['place'] : name,
        earned_at: earned[code],
        key: child&.level == :subdivision ? child.key : nil
      }
    end

    def subdivision_cards
      art = definition.card['art']
      zoom = definition.card.fetch('child_zoom', DEFAULT_CHILD_ZOOM)
      rarities = definition.card.fetch('rarities', {})

      definition.regions.map do |code, name|
        lat, lon = region_centroids[code] || [art['lat'], art['lon']]

        child_card(name: name, code: code, rarity: rarities.fetch(code, 'Common'), lat: lat, lon: lon,
                   zoom: zoom, earned_at: earned[code])
      end
    end

    def country_cards
      definition.region_codes.filter_map do |code|
        child = Registry.find("country_#{code.downcase}")
        next if child.nil?

        country_card(child, visited_at: earned[code])
      end
    end

    def country_card(child, visited_at:)
      art = child.card['art']
      progress = self.class.new(definition: child, state: state)
      link_key = child.level == :subdivision ? child.key : nil

      {
        name: child.card['place'],
        code: child.country,
        key: link_key,
        share_key: link_key ? nil : child.key,
        rarity: child.card['rarity'],
        map_lat: art['lat'],
        map_lon: art['lon'],
        map_zoom: art['zoom'],
        marker_lat: art['lat'],
        marker_lon: art['lon'],
        percent: progress.percent,
        completed: progress.completed?,
        locked: visited_at.blank? && progress.locked?,
        earned_label: country_label(progress, visited_at)
      }
    end

    def country_label(progress, visited_at)
      return progress.earned_label if progress.completed? || progress.percent.positive?
      return 'Visited' if visited_at.present?

      'Locked'
    end

    def child_card(name:, code:, rarity:, lat:, lon:, zoom:, earned_at:, key: nil)
      {
        name: name,
        code: code,
        key: key,
        rarity: rarity,
        map_lat: lat,
        map_lon: lon,
        map_zoom: zoom,
        marker_lat: lat,
        marker_lon: lon,
        percent: earned_at ? 100 : 0,
        completed: earned_at.present?,
        locked: earned_at.blank?,
        earned_label: earned_at ? "Unlocked · #{Date.parse(earned_at).strftime('%-d %b %Y')}" : nil
      }
    end

    # ST_PointOnSurface, not ST_Centroid: a ring-shaped region's centroid can
    # land inside an enclave hole (Brandenburg's falls in Berlin), which made
    # its card art a picture of the wrong region.
    def region_centroids
      @region_centroids ||= Region
                            .where(code: definition.region_codes)
                            .pluck(:code,
                                   Arel.sql('ST_Y(ST_PointOnSurface(geom::geometry))'),
                                   Arel.sql('ST_X(ST_PointOnSurface(geom::geometry))'))
                            .to_h { |code, lat, lon| [code, [lat, lon]] }
    end
  end
end
