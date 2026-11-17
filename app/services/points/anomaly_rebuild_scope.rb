# frozen_string_literal: true

# Which years an anomaly re-check has to rebuild. Before the reset it stores a
# per-year fingerprint of the user's flagged points in their settings; after
# the re-filter it compares that with the current flags.
#
# The fingerprint is persisted, not held in memory, so a run that dies or is
# retried after the reset still compares against the flags it started from.
# Comparing against flags an earlier attempt already re-filtered would find
# nothing changed and skip a rebuild that never happened. It is written only
# when absent and forgotten only after the rebuild is under way.
class Points::AnomalyRebuildScope
  SETTINGS_KEY = 'anomaly_rebuild_fingerprint'
  # The flags as this run found them. When an older SETTINGS_KEY was kept, the
  # live filter may have flagged points since; comparing with both only ever
  # adds years. Stored too, so a resumed run still has it.
  LATEST_KEY = 'anomaly_rebuild_fingerprint_latest'
  SETTINGS_OBJECT = "CASE WHEN jsonb_typeof(settings) = 'object' THEN settings ELSE '{}'::jsonb END"

  def initialize(user)
    @user = user
  end

  def remember
    current = fingerprints
    return if current.nil?

    User.where(id: user.id).update_all(
      ["settings = #{SETTINGS_OBJECT} || jsonb_build_object(?, ?::jsonb)", LATEST_KEY, current.to_json]
    )
    User.where(id: user.id)
        .where("NOT jsonb_exists(#{SETTINGS_OBJECT}, ?)", SETTINGS_KEY)
        .update_all(
          ["settings = #{SETTINGS_OBJECT} || jsonb_build_object(?, ?::jsonb)", SETTINGS_KEY, current.to_json]
        )
  end

  # Sorted years to rebuild, or nil when the caller cannot tell what changed:
  # nothing was stored, or the database cannot take the user's timezone.
  def changed_years
    before = stored_fingerprints(SETTINGS_KEY)
    return if before.nil?

    after = fingerprints
    return if after.nil?

    latest = stored_fingerprints(LATEST_KEY)
    changed = years_differing(before, after)
    changed |= years_differing(latest, after) if latest
    with_years_sharing_a_track(changed).sort
  end

  def forget
    User.where(id: user.id).where("jsonb_typeof(settings) = 'object'")
        .update_all(['settings = settings - ARRAY[?, ?]::text[]', SETTINGS_KEY, LATEST_KEY])
  end

  private

  attr_reader :user

  def years_differing(before, after)
    (before.keys | after.keys).reject { |year| before[year] == after[year] }
  end

  # { year => [count, md5 of the ids, any still on a track] } of the flagged
  # points, the year taken in the user's timezone as Users::RecalculateDataJob
  # splits it. The last element catches points flagged before the filter
  # detached them from their track: re-flagging detaches them now, which
  # leaves that track's geometry stale.
  def fingerprints
    year_sql = "EXTRACT(YEAR FROM to_timestamp(timestamp) AT TIME ZONE #{Point.connection.quote(zone_name)})::int"

    user.points.where(anomaly: true).group(Arel.sql(year_sql))
        .pluck(
          Arel.sql(year_sql),
          Arel.sql("count(*), md5(string_agg(id::text, ',' ORDER BY id)), bool_or(track_id IS NOT NULL)")
        )
        .to_h { |year, count, digest, on_track| [year, [count, digest, on_track]] }
  rescue ActiveRecord::StatementInvalid => e
    # A zone name Ruby knows but the server's tzdata does not.
    Rails.logger.warn("[AnomalyRebuildScope] User #{user.id}: no fingerprint (#{e.class}), rebuilding all years")
    nil
  end

  def stored_fingerprints(key)
    stored = User.where(id: user.id).pick(Arel.sql("settings -> #{Point.connection.quote(key)}"))
    stored = JSON.parse(stored) if stored.is_a?(String)
    stored&.to_h { |year, fingerprint| [year.to_i, fingerprint] }
  end

  # Rebuilding a year deletes every track overlapping it, including one that
  # runs over New Year, so the year on the other side is rebuilt too.
  def with_years_sharing_a_track(years)
    result = years.dup
    pending = years.dup

    while (year = pending.shift)
      [[year, year - 1], [year + 1, year + 1]].each do |boundary_year, neighbour|
        next if result.include?(neighbour) || !track_crosses_new_year?(boundary_year)

        result << neighbour
        pending << neighbour
      end
    end

    result
  end

  def track_crosses_new_year?(year)
    new_year = Time.find_zone!(zone_name).local(year)
    user.tracks.where('start_at < :at AND end_at > :at', at: new_year).exists?
  end

  def zone_name
    @zone_name ||= (Time.find_zone(user.timezone) || Time.find_zone!(ENV.fetch('TIME_ZONE', 'UTC'))).tzinfo.name
  end
end
