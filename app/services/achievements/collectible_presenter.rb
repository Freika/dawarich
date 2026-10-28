# frozen_string_literal: true

module Achievements
  class CollectiblePresenter
    attr_reader :card

    def initialize(card, public: false)
      @card = card
      @public = public
      if @public && card.geographic?
        @card = card.dup
        @card.id = card.id
        @card.data = card.data.fetch('public')
        @card.level = @card.data.fetch('levels').keys.map(&:to_i).max || 0
        @card.earned_at = @card.data.fetch('levels')[@card.level.to_s]
      end
      return unless @public && card.series == 'city' && card.city_selection&.share_mosaic?

      snapshot = Exploration::Snapshot.find_by!(id: card.data['snapshot_id'], user_id: card.user_id)
      result = CityRule.call(card.user, card.city_selection, snapshot,
                             privacy_zone_masker: Maps::PrivacyZoneMasker.new(card.user))
      @card = card.dup
      @card.id = card.id
      @card.city_selection = card.city_selection
      @card.data = result.fetch(:data)
      @card.level = @card.data.fetch('levels').keys.map(&:to_i).max || 0
      @card.earned_at = @card.data.fetch('levels')[@card.level.to_s]
    end

    def name
      return t("milestones.#{card.subject_key}") if card.series == 'milestone'
      return t('national_parks') if card.series == 'parks'

      "#{series_name} · #{card.data['name']}"
    end

    def series_name
      key = if card.series == 'seasons' && card.data['latitude'].to_f.abs < 23.44
              'year_round'
            else
              card.series
            end
      t("series.#{key}")
    end

    def rarity
      return %w[Common Common Rare Epic Legendary][card.level.clamp(0, 4)] if card.series == 'city'
      return 'Epic' if card.series == 'seasons'
      return 'Rare' if card.series == 'park'
      return %w[Common Common Rare Epic][card.level.clamp(0, 3)] if card.series == 'parks'

      if card.series == 'milestone'
        return 'Legendary' if card.subject_key == 'antarctic'

        return %w[arctic four_quarters].include?(card.subject_key) ? 'Epic' : 'Rare'
      end

      %w[Rare Rare Epic Legendary][card.level.clamp(0, 3)]
    end

    def locked?
      card.data.fetch('progress', 0).zero?
    end

    def completed?
      card.unlocked?
    end

    def percent
      return card.data.fetch('progress', 0).round.clamp(0, 100) if card.series == 'city'
      return 100 if completed?

      (card.data.fetch('progress', 0).to_f * 100 / card.data.fetch('target', 1)).round.clamp(0, 100)
    end

    def completed_on
      card.earned_at&.in_time_zone(card.data['timezone'] || 'UTC')&.to_date
    end

    def metric_label
      case card.series
      when 'city'
        if @public && !card.city_selection&.share_mosaic?
          return t('city_public_level', percent: card.level.positive? ? CityRule::THRESHOLDS[card.level - 1] : 0)
        end

        t('city_progress', percent: format('%.1f', card.data.fetch('progress', 0)),
                           area: format('%.2f', card.data.fetch('opened_area', 0) / 1_000_000.0))
      when 'return'
        completed? ? t('return_years', count: ReturnRule::YEARS.fetch(card.level - 1)) : t('return_waiting')
      when 'park'
        t('park_progress', minutes: (card.data.fetch('progress', 0) / 60.0).floor)
      when 'parks'
        return "#{t('national_parks')}: #{card.data.fetch('progress', 0)}" if card.data.fetch('progress', 0) >= 15

        t('parks_progress', count: card.data.fetch('progress', 0), target: card.data.fetch('target', 1))
      when 'milestone'
        t('regions_progress', count: card.data.fetch('progress', 0), target: card.data.fetch('target', 1))
      else
        t('seasons_progress', count: card.data.fetch('progress', 0))
      end
    end

    def card_attributes
      {
        name: name, rarity: rarity, map_lat: card.data['latitude'] || 0,
        map_lon: card.data['longitude'] || 0, map_zoom: 10,
        description: t("description.#{card.series}"), percent: percent, completed: completed?, locked: locked?,
        earned_label: completed? ? I18n.t('achievements.cards.status.unlocked_on', date: I18n.l(completed_on)) : nil,
        metric_label: metric_label, silhouette: SeriesArtwork.call(card, public: @public),
        geography_key: "collectible-#{card.series}-#{card.subject_key}"
      }
    end

    def evidence_rows
      if card.series == 'milestone'
        return card.data.fetch('regions', []).map do |region|
          minutes = I18n.t('units.minutes_compact', value: "#{region.fetch('seconds') / 60}/10")
          label = "#{t("regions.#{region.fetch('region')}")} · #{minutes}"
          { label: label, at: region['at'] && Time.iso8601(region['at']).in_time_zone(region['timezone'] || 'UTC') }
        end
      end

      card.data.fetch('evidence', []).map do |evidence|
        label = case card.series
                when 'seasons'
                  index = evidence.fetch('season')
                  if card.data['latitude'].to_f.abs < 23.44
                    t("periods.#{index}")
                  else
                    names = if card.data['latitude'].to_f.negative?
                              %w[summer autumn winter
                                 spring]
                            else
                              %w[winter spring summer autumn]
                            end
                    t("seasons.#{names[index]}")
                  end
                when 'milestone'
                  t("regions.#{evidence.fetch('region')}")
                when 'parks'
                  evidence.fetch('name')
                when 'park'
                  t('observed_time', minutes: (evidence.fetch('seconds') / 60.0).floor)
                else
                  t('recorded_visit')
                end
        zone = evidence['timezone'] || card.data['timezone'] || 'UTC'
        { label: label, at: Time.iso8601(evidence.fetch('at')).in_time_zone(zone),
          visit_ids: evidence['visit_ids'] || [] }
      end
    end

    def history_rows
      card.events.order(:created_at, :id).map do |event|
        version = card.dup
        version.level = event.level
        { rarity: self.class.new(version).rarity, kind: event.kind, at: event.occurred_at,
          detected_at: event.created_at }
      end
    end

    private

    def t(key, **options)
      I18n.t("achievements.collections.#{key}", **options)
    end
  end
end
