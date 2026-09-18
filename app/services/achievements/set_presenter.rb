# frozen_string_literal: true

module Achievements
  class SetPresenter
    DEFAULT_CHILD_ZOOM = 6

    attr_reader :definition, :state, :sharing, :timezone

    def initialize(definition:, state: {}, sharing: nil, timezone: 'UTC')
      @definition = definition
      @state = state || {}
      @sharing = sharing
      @timezone = timezone
    end

    delegate :total, :target, :flat?, :level, :parent_key, to: :definition

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

      earned.values.map { |date| local_date(date) }.sort[target - 1]
    end

    def earned_label
      return translate('status.locked') if locked?
      return translate('status.unlocked_on', date: localized_date(completed_on)) if completed?

      # Absolute count, not a percent: the plate bar already shows how far,
      # so the label carries the number the bar can't.
      progress_metric(display_count, target)
    end

    def celebrate?
      completed? && state.dig('celebrated', definition.key).blank?
    end

    def rarity
      definition.card['rarity']
    end

    def name
      return definition.name if definition.kind == 'region_set'
      return place if definition.flat?

      translate('explorer_name', place: place)
    end

    def description
      if definition.kind == 'continent'
        translate('description.continent', count: total, place: place)
      elsif definition.kind == 'country' && definition.level == :subdivision
        translate('description.regions', count: total, place: place)
      elsif definition.kind == 'country'
        translate('description.country', place: place)
      else
        definition.card['description']
      end
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
        name: name,
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
        earned_label: earned_label,
        geography_key: definition.key,
        silhouette: silhouette,
        metric_label: progress_metric(display_count, target)
      }
    end

    def region_cards
      cards = level == :subdivision ? subdivision_cards : country_cards

      cards.sort_by { |card| [card[:locked] ? 1 : 0, card[:name]] }
    end

    private

    def silhouette
      @silhouette ||= if definition.kind == 'country'
                        RegionSilhouettes.new(level: :country, codes: [definition.country]).call[definition.country]
                      else
                        RegionSilhouettes.collection(codes: definition.region_codes, key: definition.key)
                      end
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
      progress = self.class.new(definition: child, state: state, timezone: timezone)
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
      return translate('status.visited') if visited_at.present?

      translate('status.locked')
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
        earned_label: earned_at ? translate('status.unlocked_on', date: localized_date(local_date(earned_at))) : nil
      }
    end

    def progress_metric(count, total)
      translate("metric.#{level == :country ? 'countries' : 'regions'}", count: count, total: total)
    end

    def localized_date(date)
      I18n.l(date, format: translate('date_format'))
    end

    def translate(key, **options)
      I18n.t("achievements.cards.#{key}", **options)
    end

    def local_date(value)
      Time.iso8601(value).in_time_zone(timezone).to_date
    rescue ArgumentError
      Date.parse(value)
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
