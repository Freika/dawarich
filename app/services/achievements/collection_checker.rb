# frozen_string_literal: true

module Achievements
  class CollectionChecker
    def initialize(user, notify: true)
      @user = user
      @notify = notify
    end

    def call
      CollectionState.with_advisory_lock("achievement-collections-#{@user.id}", timeout_seconds: 0) do
        @state = CollectionState.create_or_find_by!(user_id: @user.id)
        if @user.achievement_city_selections.exists?
          Exploration::Rebuild.new(@user).call
          state = Exploration::State.find_by!(user_id: @user.id)
          @snapshot = Exploration::Snapshot.find_by(id: state.snapshot_id, user_id: @user.id)
          return unless @snapshot && state.revision == state.published_revision
        end
        dataset = Exploration::Geography.current
        dataset ||= Exploration::Geography.install! if @user.points.exists?
        @dataset = dataset
        @notify &&= @state.published_dataset_id == dataset&.id
        @notify &&= @state.timezone_version == LocationTimezone.version
        3.times do
          Selection.where(user: @user).includes(:place).order(:id).each { |selection| resolve_timezone(selection) }
          @state.reload
          return if @state.current?

          @revision = @state.revision
          @selections = Selection.where(user: @user).includes(:place).order(:id).to_a
          break if @selections.all? { |selection| timezone_coordinates_match?(selection) }
        end
        return unless @selections.all? { |selection| timezone_coordinates_match?(selection) }

        results = @selections.flat_map { |selection| place_results(selection) }
        city_selections = @user.achievement_city_selections.to_a
        return if city_selections.any? && @snapshot.nil?

        results.concat(city_selections.filter_map { |selection| CityRule.call(@user, selection, @snapshot) })
        fingerprint = PrivacyFingerprint.call(@user)
        @privacy_fingerprint = fingerprint
        masker = Maps::PrivacyZoneMasker.new(@user)
        ApplicationRecord.transaction do
          observations = @user.points.exists? ? ObservedTime.new(@user, dataset: dataset).call : {}
          public_observations = if masker.any? && @user.points.exists?
                                  ObservedTime.new(@user, dataset: dataset, privacy_zone_masker: masker,
                                                         prepare_flights: false).call
                                else
                                  observations
                                end
          geographic = GeographicResults.call(dataset, observations)
          public_results = GeographicResults.call(dataset, public_observations)
          geographic.each do |result|
            public_result = public_results.find do |item|
              item[:series] == result[:series] && item[:subject_key] == result[:subject_key]
            end
            result[:data]['public'] =
              public_result&.fetch(:data) || result[:data].merge('levels' => {}, 'progress' => 0, 'evidence' => [])
            result[:data]['privacy_fingerprint'] = fingerprint
          end
          results.concat(geographic)
        end
        publish(results, @revision)
      ensure
        @state&.update_columns(requested_at: nil)
      end
    rescue StandardError
      @state&.update_columns(failed_at: Time.current, requested_at: nil)
      raise
    end

    private

    def resolve_timezone(selection)
      place = selection.place
      source_current = selection.timezone_source == 'manual' || selection.timezone_source == LocationTimezone.version
      return if selection.timezone.present? && source_current && timezone_coordinates_match?(selection)

      selection.update!(timezone: LocationTimezone.call(place.lat, place.lon),
                        timezone_source: LocationTimezone.version,
                        timezone_latitude: place.lat, timezone_longitude: place.lon)
    end

    def timezone_coordinates_match?(selection)
      selection.timezone_latitude == selection.place.lat.to_d.round(7) &&
        selection.timezone_longitude == selection.place.lon.to_d.round(7)
    end

    def place_results(selection)
      place = selection.place
      common = { 'name' => place.name, 'latitude' => place.lat, 'longitude' => place.lon,
                 'timezone' => selection.timezone, 'timezone_source' => selection.timezone_source,
                 'archived' => place.archived? }
      intervals = selection.timezone ? PlaceHistory.new(selection).call : []
      %w[return seasons].map do |series|
        result = if selection.timezone.nil?
                   { 'status' => 'timezone_required', 'progress' => 0, 'target' => series == 'seasons' ? 4 : 1,
                     'levels' => {}, 'evidence' => [] }
                 elsif series == 'return'
                   ReturnRule.call(intervals, timezone: selection.timezone)
                 else
                   SeasonsRule.call(intervals, timezone: selection.timezone)
                 end
        { series: series, subject_key: "place:#{place.id}", selection_id: selection.id,
          data: common.merge('status' => 'ready').merge(result) }
      end
    end

    def publish(results, revision)
      @fresh_cards = []
      @state.with_lock do
        return unless @state.revision == revision
        return if @snapshot && Exploration::State.find_by(user_id: @user.id)&.revision != @snapshot.revision
        return unless Exploration::Geography.current&.id == @dataset&.id

        return unless PrivacyFingerprint.call(@user) == @privacy_fingerprint

        keys = results.map { |result| [result[:series], result[:subject_key]] }
        @user.achievement_collectibles.find_each do |card|
          next if keys.include?([card.series, card.subject_key])

          write_card(card, card.data.merge('levels' => {}, 'status' => 'removed'), selection_id: nil,
city_selection_id: nil)
        end
        results.each do |result|
          result[:data]['source_revision'] = revision
          card = @user.achievement_collectibles.find_or_initialize_by(series: result[:series],
                                                                      subject_key: result[:subject_key])
          write_card(card, result[:data], selection_id: result[:selection_id],
                     city_selection_id: result[:city_selection_id])
        end
        @state.update!(published_revision: revision, published_dataset_id: @dataset&.id,
                       privacy_fingerprint: @privacy_fingerprint,
                       timezone_version: LocationTimezone.version,
                       completed_at: Time.current, failed_at: nil)
        notify_cards
      end
    end

    def write_card(card, data, selection_id:, city_selection_id:)
      levels = data.fetch('levels')
      level = levels.keys.map(&:to_i).max || 0
      previous = card.level
      card.assign_attributes(data: data, level: level, selection_id: selection_id, city_selection_id: city_selection_id,
                             earned_at: levels[level.to_s],
                             revoked_at: data['status'] == 'removed' ? Time.current : nil)
      card.sharing_enabled = false if level.zero? && previous.positive? || data['status'] == 'removed'
      card.save!
      card.events.create!(kind: 'revoked', level: previous, occurred_at: Time.current) if previous > level
      fresh = levels.keys.map(&:to_i).sort.filter_map do |earned_level|
        next if card.events.exists?(kind: 'earned', level: earned_level)

        card.events.create!(kind: 'earned', level: earned_level, occurred_at: levels.fetch(earned_level.to_s))
      end
      return if fresh.empty? || !@notify || @state.completed_at.nil?

      UnlockEvent.create_or_find_by!(user_id: @user.id, kind: 'collectible', key: "#{card.id}:#{level}")
      @fresh_cards << card
    end

    def notify_cards
      return if @fresh_cards.empty?

      I18n.with_locale(@user.locale) do
        if @fresh_cards.size > 5
          ::Notifications::Create.new(user: @user, kind: :info,
                                      title: I18n.t('achievements.notifications.digest_title',
                                                    count: @fresh_cards.size),
                                      content: I18n.t('achievements.collections.notification_content')).call
          return
        end
        @fresh_cards.each do |card|
          ::Notifications::Create.new(user: @user, kind: :info,
                                      title: I18n.t('achievements.collections.notification_title',
                                                    name: CollectiblePresenter.new(card).name),
                                      content: I18n.t('achievements.collections.notification_content')).call
        end
      end
    end
  end
end
