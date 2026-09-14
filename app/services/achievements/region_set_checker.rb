# frozen_string_literal: true

module Achievements
  class RegionSetChecker
    # Above this many newly earned regions in one run (a big import backfill),
    # collapse the per-region announcements into a single digest notification.
    REGION_NOTIFY_CAP = 5

    COMMIT_ATTEMPTS = 2

    def initialize(user, notify: true, oldest_timestamp: nil)
      @user = user
      @notify = notify
      @oldest_timestamp = oldest_timestamp
    end

    def call
      @cursor = latest_timestamp
      return if @cursor.nil?

      @progress = fetch_progress
      @newly_earned = []

      COMMIT_ATTEMPTS.times do
        previous = @progress.reload.state['cursor'].to_i
        break if settled?(previous)

        replace = recompute?(previous)
        deltas = collect_deltas(replace ? 0 : previous)
        break if commit(deltas, replace: replace, expected: previous)

        @newly_earned.clear
      end

      award_and_notify(@progress.reload, @newly_earned)
    end

    private

    # Race-safe against a concurrent CheckJob for the same user: the uniqueness
    # validation means create_or_find_by can't be used, so recover from the
    # database unique index instead.
    def fetch_progress
      Progress.find_or_create_by!(user_id: user.id, achievement_key: Progress::EXPLORATION_KEY)
    rescue ActiveRecord::RecordNotUnique
      Progress.find_by!(user_id: user.id, achievement_key: Progress::EXPLORATION_KEY)
    end

    attr_reader :user, :notify, :oldest_timestamp

    def settled?(previous)
      previous.positive? && @cursor <= previous && !recompute?(previous)
    end

    def commit(deltas, replace:, expected:)
      committed = false

      @progress.with_lock do
        next unless @progress.state['cursor'].to_i == expected

        @progress.update!(
          state: merged_state(@progress.state, deltas, @newly_earned, replace: replace, cursor: @cursor)
        )
        committed = true
      end

      committed
    end

    def latest_timestamp
      user.points.not_anomaly.where.not(lonlat: nil).maximum(:timestamp)
    end

    def recompute?(cursor)
      oldest_timestamp.present? && cursor.positive? && oldest_timestamp < cursor
    end

    def collect_deltas(since)
      CountryDwellCalculator.new(user, since: since).call
                            .merge(GridDwellCalculator.new(user, table: 'regions', since: since).call)
    end

    def merged_state(state, deltas, newly_earned, replace:, cursor:)
      dwell = replace ? {} : state.fetch('dwell', {})
      earned = state.fetch('earned', {})

      deltas.each { |code, delta| dwell[code] = dwell.fetch(code, 0) + delta }

      dwell.each do |code, seconds|
        next if earned.key?(code) || seconds < threshold_seconds

        earned[code] = Time.current.iso8601
        newly_earned << code
      end

      state.merge('cursor' => cursor, 'dwell' => dwell, 'earned' => earned)
    end

    def threshold_seconds
      @threshold_seconds ||= user.safe_settings.min_minutes_spent_in_city * 60
    end

    def award_and_notify(progress, newly_earned)
      earned = progress.state.fetch('earned', {})
      awarded = user.user_achievements.pluck(:achievement_key).to_set
      completed = Registry.all.filter_map { |definition| definition if award?(definition, earned, awarded) }

      notify_regions(newly_earned, earned)
      completed.each { |definition| notify_completion(definition) }
    end

    def award?(definition, earned, awarded)
      return false if awarded.include?(definition.key)
      return false if (definition.region_codes & earned.keys).size < definition.target

      UserAchievement.find_or_create_by!(user: user, achievement_key: definition.key) do |award|
        award.earned_at = Time.current
      end.previously_new_record?
    rescue ActiveRecord::RecordNotUnique
      false # created concurrently by another job; this run did not newly earn it
    end

    def notify_regions(newly_earned, earned)
      return unless notify
      return notify_region_digest(newly_earned) if newly_earned.size > REGION_NOTIFY_CAP

      newly_earned.each do |code|
        definition = announcer_for(code)
        next if definition.nil?

        ::Notifications::Create.new(
          user: user, kind: :info,
          title: "#{definition.regions[code]} explored!",
          content: "#{definition.name}: #{[(definition.region_codes & earned.keys).size, definition.target].min}" \
                   "/#{definition.target} regions visited."
        ).call
      end
    end

    def notify_region_digest(newly_earned)
      ::Notifications::Create.new(
        user: user, kind: :info,
        title: "#{newly_earned.size} new regions explored!",
        content: 'Your latest data unlocked new regions — see them all on the Achievements page.'
      ).call
    end

    def notify_completion(definition)
      return unless notify
      # World tiers are currently hidden from the UI; award silently.
      return if definition.kind == 'region_set'

      ::Notifications::Create.new(
        user: user, kind: :info,
        title: "#{definition.name} completed!",
        content: "You explored #{definition.threshold ? definition.target : "all #{definition.total}"} regions."
      ).call
    end

    def announcer_for(code)
      announcers[code]
    end

    def announcers
      @announcers ||= (gridded_countries + continents).each_with_object({}) do |definition, index|
        definition.region_codes.each { |code| index[code] ||= definition }
      end
    end

    def gridded_countries
      Registry.all.select { |definition| definition.kind == 'country' && definition.level == :subdivision }
    end

    def continents
      Registry.all.select { |definition| definition.kind == 'continent' }
    end
  end
end
