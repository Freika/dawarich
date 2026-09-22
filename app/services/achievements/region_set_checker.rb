# frozen_string_literal: true

module Achievements
  class RegionSetChecker
    CALCULATION_VERSION = 3

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
      @progress = Progress.find_by(user_id: user.id, achievement_key: Progress::EXPLORATION_KEY)
      return if @progress.nil? && !eligible_points.exists?

      @progress ||= fetch_progress
      @newly_earned = []

      COMMIT_ATTEMPTS.times do
        state = @progress.reload.state
        previous = state['cursor'].to_i
        previous_inserted = state['inserted_through']
        @cursor, @inserted_through = latest_position(previous, previous_inserted)
        break if @cursor.nil?
        break if settled?(previous, previous_inserted, state)

        replace = recompute?(previous, previous_inserted) || calculation_changed?(state)
        deltas = if threshold_changed?(state) && @cursor <= previous && !replace
                   {}
                 else
                   collect_deltas(replace ? 0 : previous)
                 end
        break if commit(deltas, replace: replace, expected: previous, expected_inserted: previous_inserted)

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

    def settled?(previous, previous_inserted, state)
      previous.positive? && @cursor <= previous && @inserted_through == previous_inserted &&
        !recompute?(previous, previous_inserted) && !threshold_changed?(state) &&
        state['calculation_version'].to_i >= CALCULATION_VERSION
    end

    def commit(deltas, replace:, expected:, expected_inserted:)
      committed = false

      @progress.with_lock do
        current_state = @progress.state
        next unless current_state['cursor'].to_i == expected &&
                    current_state['inserted_through'] == expected_inserted

        # Point deletion may make the current maximum look older. Keep the
        # cursor monotonic so the next incremental pass cannot count old dwell again.
        committed_cursor = [@cursor, expected].max

        new_codes = []
        @progress.update!(
          state: merged_state(current_state, deltas, new_codes, replace: replace, cursor: committed_cursor,
                              inserted_through: @inserted_through)
        )
        UnlockEvent.enqueue_geographies!(user_id: user.id, codes: new_codes) if notify
        @newly_earned.concat(new_codes)
        committed = true
      end

      committed
    end

    def eligible_points
      user.points.where.not(lonlat: nil).where('anomaly IS DISTINCT FROM TRUE')
    end

    # Timestamp alone cannot identify buffered device uploads: a newly inserted
    # point can be older than the timestamp cursor. Track the latest insertion
    # time as a second watermark and rebuild when unseen rows fall behind the cursor.
    def latest_position(cursor, inserted_through)
      latest_insert = eligible_points.maximum(:created_at)
      return [nil, nil] if latest_insert.nil? && cursor.zero? && inserted_through.nil?

      since = inserted_through && Time.iso8601(inserted_through)
      latest_timestamp = if oldest_timestamp.present?
                           eligible_points.maximum(:timestamp)
                         elsif latest_insert && (since.nil? || latest_insert > since)
                           inserted_after(since).where('created_at <= ?', latest_insert).maximum(:timestamp)
                         end

      [[cursor, [latest_timestamp.to_i, Time.current.to_i].min].max,
       [since, latest_insert].compact.max&.utc&.iso8601(6)]
    end

    def inserted_after(since)
      since ? eligible_points.where('created_at > ?', since) : eligible_points
    end

    def recompute?(cursor, inserted_through)
      (oldest_timestamp.present? && cursor.positive? && oldest_timestamp <= cursor) ||
        historical_points_inserted?(cursor, inserted_through)
    end

    def historical_points_inserted?(cursor, inserted_through)
      return false unless cursor.positive? && @inserted_through != inserted_through

      inserted_after(inserted_through && Time.iso8601(inserted_through))
        .where('created_at <= ?', Time.iso8601(@inserted_through))
        .where('timestamp < ?', cursor).exists?
    end

    def collect_deltas(since)
      CountryDwellCalculator.new(user, since: since, through: @cursor).call
                            .merge(GridDwellCalculator.new(user, table: 'regions', since: since,
                                                                through: @cursor).call)
    end

    def merged_state(state, deltas, newly_earned, replace:, cursor:, inserted_through:)
      dwell = replace ? {} : state.fetch('dwell', {})
      earned = state.fetch('earned', {})

      deltas.each { |code, delta| dwell[code] = dwell.fetch(code, 0) + delta }

      dwell.each do |code, seconds|
        next if earned.key?(code) || seconds < threshold_seconds

        earned[code] = Time.current.iso8601
        newly_earned << code
      end

      state.except('point_id_cursor').merge(
        'cursor' => cursor,
        'inserted_through' => inserted_through,
        'dwell' => dwell,
        'earned' => earned,
        'threshold_seconds' => threshold_seconds,
        'calculation_version' => CALCULATION_VERSION
      )
    end

    def threshold_changed?(state)
      state['threshold_seconds'].to_i != threshold_seconds
    end

    def calculation_changed?(state)
      state['calculation_version'].to_i < CALCULATION_VERSION
    end

    def threshold_seconds
      @threshold_seconds ||= user.safe_settings.min_minutes_spent_in_city * 60
    end

    def award_and_notify(progress, newly_earned)
      earned = progress.state.fetch('earned', {})
      awarded = user.user_achievements.pluck(:achievement_key).to_set
      completed = Registry.all.filter_map { |definition| definition if award?(definition, earned, awarded) }

      I18n.with_locale(user.locale) do
        notify_regions(newly_earned, earned)
        completed.each { |definition| notify_completion(definition) }
      end
    end

    def award?(definition, earned, awarded)
      return false if awarded.include?(definition.key)
      return false if (definition.region_codes & earned.keys).size < definition.target

      UserAchievement.transaction do
        award = UserAchievement.find_or_create_by!(user: user, achievement_key: definition.key) do |new_award|
          new_award.earned_at = Time.current
        end
        next false unless award.previously_new_record?

        UnlockEvent.enqueue_set!(user_id: user.id, definition: definition) if notify
        true
      end
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
          title: I18n.t('achievements.notifications.region_title', region: definition.regions[code]),
          content: I18n.t(
            "achievements.notifications.#{notification_progress_key(definition)}",
            achievement: achievement_name(definition),
            count: [(definition.region_codes & earned.keys).size, definition.target].min,
            total: definition.target
          )
        ).call
      end
    end

    def notify_region_digest(newly_earned)
      ::Notifications::Create.new(
        user: user, kind: :info,
        title: I18n.t('achievements.notifications.digest_title', count: newly_earned.size),
        content: I18n.t('achievements.notifications.digest_content')
      ).call
    end

    def notify_completion(definition)
      return unless notify
      # World tiers are currently hidden from the UI; award silently.
      return if definition.kind == 'region_set'

      ::Notifications::Create.new(
        user: user, kind: :info,
        title: I18n.t('achievements.notifications.completion_title', achievement: achievement_name(definition)),
        content: completion_content(definition)
      ).call
    end

    def notification_progress_key(definition)
      definition.level == :country ? 'country_content' : 'region_content'
    end

    def completion_content(definition)
      return I18n.t('achievements.notifications.completion_country') if definition.flat?

      unit = definition.level == :country ? 'countries' : 'regions'
      quantifier = definition.threshold ? 'target' : 'all'
      count = definition.threshold || definition.total
      I18n.t("achievements.notifications.completion_#{quantifier}_#{unit}", count: count)
    end

    def announcer_for(code)
      announcers[code]
    end

    def achievement_name(definition)
      SetPresenter.new(definition: definition).name
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
