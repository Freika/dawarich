# frozen_string_literal: true

module Stats
  class RefreshToponyms
    def initialize(user, year, month, invalidate_cache: false, only_if_changed: false)
      @user = user
      @year = year
      @month = month
      @invalidate_cache = invalidate_cache
      @only_if_changed = only_if_changed
    end

    def call
      changed = false
      Stat.transaction do
        stat = user.stats.select(:id, :toponyms).lock.find_by(year: year, month: month)
        return !points.exists? unless stat

        source = source_signature
        return true if @only_if_changed && Rails.cache.read(checkpoint_key) == signature(source, stat[:toponyms])

        value = Toponyms.new(
          each_point,
          min_minutes_spent_in_city: user.safe_settings.min_minutes_spent_in_city
        ).call.as_json
        if stat[:toponyms] != value
          preserve_sweep_watermark
          stat.update_columns(toponyms: value, updated_at: Time.current)
          changed = true
        end
        Rails.cache.write(checkpoint_key, signature(source, value), expires_in: 7.days)
      end
      if changed || @invalidate_cache
        ActiveRecord.after_all_transactions_commit do
          cache = Cache::InvalidateUserCaches.new(user.id, year: year)
          cache.invalidate_countries_visited
          cache.invalidate_cities_visited
          cache.invalidate_insights_digest
        end
      end
      true
    end

    private

    attr_reader :user, :year, :month

    def checkpoint_key
      "stats/toponyms_source/v1/#{user.id}/#{year}/#{month}"
    end

    def source_signature
      first = ActiveSupport::TimeZone[user.timezone_iana].local(year, month, 1)
      [Points::Revision.for_user(user.id, start_at: first.to_i, end_at: first.next_month.to_i - 1),
       user.timezone_iana, user.safe_settings.min_minutes_spent_in_city,
       Country.order(:id).pluck(:id, :name)]
    end

    def signature(source, toponyms)
      Digest::SHA256.hexdigest(canonical([source, toponyms]).to_json)
    end

    def canonical(value)
      case value
      when Hash then value.sort.to_h.transform_values { |entry| canonical(entry) }
      when Array then value.map { |entry| canonical(entry) }
      else value
      end
    end

    def preserve_sweep_watermark
      return if user.stats_swept_at

      watermark = user.stats.maximum(:updated_at)
      User.where(id: user.id, stats_swept_at: nil).update_all(stats_swept_at: watermark)
    end

    def each_point
      Enumerator.new do |stream|
        connection = Point.connection
        cursor = "stats_toponyms_#{SecureRandom.hex(6)}"
        connection.execute("DECLARE #{cursor} NO SCROLL CURSOR FOR #{points.to_sql}")
        loop do
          batch = connection.exec_query("FETCH FORWARD 2000 FROM #{cursor}")
          break if batch.empty?

          batch.each { |row| stream << row.symbolize_keys }
        end
        connection.execute("CLOSE #{cursor}")
      end
    end

    def points
      first = ActiveSupport::TimeZone[user.timezone_iana].local(year, month, 1)
      user.points.not_anomaly
          .where(timestamp: first.to_i...first.next_month.to_i)
          .select(:id, :timestamp, :city, :country_name, :country_id, :velocity)
          .order(:timestamp, :id)
    end
  end
end
