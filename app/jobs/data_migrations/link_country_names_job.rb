# frozen_string_literal: true

# Links points whose country name the earlier backfills could not resolve: names
# in a geocoder's configured language ("Deutschland") that are neither a seed
# name nor an alias. Rows geocoded by country code store such a name next to the
# right country_id, so the instance's own linked rows say which country each
# name means. One walk over the table tallies those pairs and a second links the
# rows still NULL. Both walk primary-key ranges, so a batch costs the same at
# any table size.
class DataMigrations::LinkCountryNamesJob < ApplicationJob
  queue_as :data_migrations

  BATCH_SIZE = 50_000
  # Floor for the halving below, as in BackfillPointCountryIdJob.
  MIN_BATCH_SIZE = 5_000
  PAUSE = 5.seconds
  LOCK_TIMEOUT = '2s'
  STATEMENT_TIMEOUT = '5min'
  MAX_ATTEMPTS = 10
  # A few mislabelled rows must not block a name; an even split is no evidence.
  MIN_SHARE = 0.99

  retry_on ActiveRecord::LockWaitTimeout, ActiveRecord::QueryAborted,
           wait: 1.minute, attempts: MAX_ATTEMPTS do |job, error|
    args = job.arguments.map(&:inspect).join(', ')
    Rails.logger.error(
      "[LinkCountryNames] gave up after #{MAX_ATTEMPTS} attempts (#{error.class}: #{error.message}). " \
      "Resume with: DataMigrations::LinkCountryNamesJob.perform_later(#{args})"
    )
  end

  def perform(phase = 'tally', start_id = nil, data = {}, batch_size = BATCH_SIZE)
    start_id ||= Point.minimum(:id)
    return if start_id.nil?

    end_id = start_id + batch_size - 1
    # Read before the batch: everything after the tally must not raise into the
    # rescue below, which retries with data as it was before this batch.
    max_id = Point.maximum(:id).to_i
    data = tally(start_id, end_id, data) if phase == 'tally'
    link(start_id, end_id, data) if phase == 'link'

    Rails.logger.info("[LinkCountryNames] #{phase} at id #{end_id} of #{max_id}")

    if end_id < max_id
      self.class.set(wait: PAUSE).perform_later(phase, end_id + 1, data)
    elsif phase == 'tally'
      start_linking(data)
    else
      Rails.logger.info("[LinkCountryNames] completed at id #{end_id}")
    end
  # A statement_timeout is usually size, not luck: halve and retry from the same
  # cursor, and only the smallest batch reaches retry_on. The bounded block
  # raises before tally merges anything, so data is still the pre-batch tally.
  rescue ActiveRecord::QueryAborted => e
    raise if batch_size / 2 < MIN_BATCH_SIZE

    Rails.logger.warn(
      "[LinkCountryNames] #{phase} batch #{start_id}..#{end_id} aborted (#{e.class}); " \
      "retrying from id #{start_id} at half size #{batch_size / 2}"
    )
    self.class.set(wait: PAUSE).perform_later(phase, start_id, data, batch_size / 2)
  end

  private

  def tally(start_id, end_id, tallies)
    counts = bounded do
      Point.where(id: start_id..end_id).where.not(country_id: nil).where.not(country_name: nil)
           .group(:country_name, :country_id).count
    end

    counts.each_with_object(tallies) do |((name, country_id), count), merged|
      next if name.blank? || known_names.include?(name)

      merged[name] ||= {}
      merged[name][country_id.to_s] = merged[name].fetch(country_id.to_s, 0) + count
    end
  end

  def known_names
    @known_names ||= Set.new(Country.without_geom.pluck(:name)) + Countries::NameAliases::ALIASES.keys
  end

  def start_linking(tallies)
    links = tallies.filter_map do |name, per_country|
      country_id, count = per_country.max_by(&:last)
      [name, country_id.to_i] if count >= per_country.values.sum * self.class::MIN_SHARE
    end.to_h

    Rails.logger.info("[LinkCountryNames] tallied #{tallies.size} names, #{links.size} can be linked")
    self.class.set(wait: PAUSE).perform_later('link', nil, links) if links.any?
  end

  # COALESCE mirrors BackfillPointCountryIdJob: country_name superseded country.
  # Everything is quoted or cast by hand: sanitize_sql_array would read a "?"
  # inside a quoted name as a bind placeholder.
  def link(start_id, end_id, links)
    return if links.empty?

    connection = ActiveRecord::Base.connection
    values = links.map { |name, country_id| "(#{connection.quote(name)}, #{Integer(country_id)})" }.join(', ')

    linked = bounded do
      connection.update(<<~SQL.squish)
        UPDATE points p
        SET country_id = links.country_id
        FROM (VALUES #{values}) AS links(name, country_id)
        WHERE p.id BETWEEN #{Integer(start_id)} AND #{Integer(end_id)}
          AND p.country_id IS NULL
          AND links.name = COALESCE(p.country_name, p.country)
      SQL
    end
    Rails.logger.info("[LinkCountryNames] linked #{linked} points in #{start_id}..#{end_id}")
  end

  def bounded(&)
    ActiveRecord::Base.transaction do
      ActiveRecord::Base.connection.execute("SET LOCAL lock_timeout = '#{LOCK_TIMEOUT}'")
      ActiveRecord::Base.connection.execute("SET LOCAL statement_timeout = '#{STATEMENT_TIMEOUT}'")
      yield
    end
  end
end
