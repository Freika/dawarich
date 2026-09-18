# frozen_string_literal: true

require 'timeout'

class Points::Move
  TIMEOUT_SECONDS = 3

  Result = Data.define(:point, :track, :point_revision, :track_revision, :visited_countries)

  class InvalidCoordinates < StandardError; end
  class InvalidHistoryScope < StandardError; end
  class RecalculationTimeout < StandardError; end

  class StaleEdit < StandardError
    attr_reader :result

    def initialize(result)
      @result = result
      super('The point or track was changed by another edit')
    end
  end

  def self.call(**attributes)
    new(**attributes).call
  end

  def initialize(user:, point_id:, latitude:, longitude:, point_revision:, track_revision:, history_scope:)
    @user = user
    @point_id = point_id
    @latitude = finite_coordinate(latitude, -90, 90)
    @longitude = finite_coordinate(longitude, -180, 180)
    @point_revision = integer_revision(point_revision)
    @track_revision = track_revision.nil? ? nil : integer_revision(track_revision)
    @history_scope = normalize_history_scope(history_scope)
  end

  def call
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = Timeout.timeout(TIMEOUT_SECONDS) { move_in_transaction }
    publish(result)
    enqueue_stats_recalculation(result.point)
    instrument(:success, started_at, result)
    result
  rescue StaleEdit => e
    instrument(:conflict, started_at, e.result)
    Rails.logger.info('event=point_move.conflict outcome=conflict')
    raise
  rescue Timeout::Error, ActiveRecord::QueryCanceled => e
    instrument(:timeout, started_at)
    Rails.logger.warn("event=point_move.timeout outcome=timeout error_class=#{e.class}")
    raise RecalculationTimeout, e.message
  end

  private

  attr_reader :user, :point_id, :latitude, :longitude, :point_revision, :track_revision, :history_scope

  def move_in_transaction
    Point.transaction do
      Point.connection.execute("SET LOCAL statement_timeout = '#{TIMEOUT_SECONDS}s'")
      point_identity = user.points.where(id: point_id).pick(:id, :track_id)
      raise ActiveRecord::RecordNotFound unless point_identity

      track_id = point_identity.last

      locks_started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      track = track_id && user.tracks.lock.find(track_id)
      point = user.points.lock.find(point_id)
      @lock_wait_seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - locks_started_at
      raise StaleEdit, current_result(point, track) if point.track_id != track_id

      check_revisions!(point, track)
      before_countries = visited_country_codes

      assign_position_and_country(point)
      point.save!
      # The composite MapEdits event is the single canonical publication for
      # this mutation; suppress the legacy generic Track update broadcast.
      Tracks::Recalculator.call(track, broadcast: false) if track

      after_countries = visited_country_codes
      changed_countries = before_countries == after_countries ? nil : { iso_a3: after_countries }

      current_result(point, track, changed_countries)
    end
  end

  def check_revisions!(point, track)
    stale = point.lock_version != point_revision
    stale ||= track && track_revision != track.lock_version
    raise StaleEdit, current_result(point, track) if stale
  end

  def assign_position_and_country(point)
    country = Country.containing_point(longitude, latitude)
    point.assign_attributes(
      lonlat: "POINT(#{longitude} #{latitude})",
      country_id: country&.id,
      country_name: country&.name,
      city: nil,
      reverse_geocoded_at: nil
    )
    point.write_attribute(:country, country&.name)
  end

  def current_result(point, track, visited_countries = nil)
    track&.track_segments&.reload
    Result.new(
      point: point.reload,
      track: track&.reload,
      point_revision: point.lock_version,
      track_revision: track&.lock_version,
      visited_countries: visited_countries
    )
  end

  def visited_country_codes
    Countries::VisitedQuery.new(user: user, **history_scope).call.map { |country| country[:iso_a3] }
  end

  def publish(result)
    Points::TileEpoch.bump(user.id, timestamps: [result.point.timestamp])
    MapEdits::Publisher.call(user: user, result: result)
  rescue StandardError => e
    Rails.logger.error(
      "event=point_move.post_commit_failed error_class=#{e.class} " \
      "point_id=#{result.point.id} track_id=#{result.track&.id}"
    )
    ActiveSupport::Notifications.instrument('point_move.post_commit_failure', operation: 'publish')
    record_post_commit_failure('publish')
    report_post_commit_failure(e)
  end

  def enqueue_stats_recalculation(point)
    local_time = Time.zone.at(point.timestamp).in_time_zone(user.timezone_iana)
    Stats::CalculatingJob.perform_later(user.id, local_time.year, local_time.month)
  rescue StandardError => e
    Rails.logger.error("event=point_move.post_commit_failed error_class=#{e.class} point_id=#{point.id}")
    record_post_commit_failure('stats')
    report_post_commit_failure(e)
  end

  def instrument(outcome, started_at, result = nil)
    payload = {
      outcome: outcome,
      duration: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at,
      lock_wait: @lock_wait_seconds || 0,
      point_count: result&.track&.instance_variable_get(:@recalculated_point_count) || 1,
      segment_count: result&.track&.track_segments&.size || 0
    }
    ActiveSupport::Notifications.instrument('point_move.map', **payload)
    record_move_metrics(payload)
  end

  def record_move_metrics(payload)
    outcome = payload.fetch(:outcome).to_s
    Yabeda.dawarich_map.point_moves_total.increment({ outcome: outcome })
    Yabeda.dawarich_map.point_move_duration_seconds.measure(
      { outcome: outcome }, payload.fetch(:duration)
    )
    Yabeda.dawarich_map.point_move_lock_wait_seconds.measure(
      { outcome: outcome }, payload.fetch(:lock_wait)
    )
    Yabeda.dawarich_map.point_move_track_points.measure({}, payload.fetch(:point_count))
    Yabeda.dawarich_map.point_move_track_segments.measure({}, payload.fetch(:segment_count))
  rescue StandardError => e
    Rails.logger.warn("event=point_move.metrics_failed error_class=#{e.class}")
  end

  def record_post_commit_failure(operation)
    Yabeda.dawarich_map.post_commit_failures_total.increment({ operation: operation })
  rescue StandardError => e
    Rails.logger.warn("event=point_move.metrics_failed error_class=#{e.class}")
  end

  def report_post_commit_failure(error)
    ExceptionReporter.call(error, 'Failed to invalidate or publish committed map edit')
  rescue StandardError
    nil
  end

  def finite_coordinate(value, min, max)
    number = Float(value)
    raise InvalidCoordinates unless number.finite? && number.between?(min, max)

    number
  rescue ArgumentError, TypeError
    raise InvalidCoordinates
  end

  def integer_revision(value)
    Integer(value)
  rescue ArgumentError, TypeError
    raise InvalidCoordinates
  end

  def normalize_history_scope(scope)
    values = scope.to_h.symbolize_keys
    start_at = Integer(values.fetch(:start_at))
    end_at = Integer(values.fetch(:end_at))
    raise InvalidHistoryScope if start_at > end_at

    { start_at: start_at, end_at: end_at, import_id: values[:import_id] }
  rescue KeyError, ArgumentError, TypeError
    raise InvalidHistoryScope
  end
end
