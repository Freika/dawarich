# frozen_string_literal: true

class DemoData::Destroyer
  def initialize(user)
    @user = user
  end

  def call
    return { status: :no_demo_data } unless demo_import

    affected_months = collect_affected_months
    recalc_months = []

    begin
      ActiveRecord::Base.transaction do
        @user.visits.demo.destroy_all
        @user.trips.demo.destroy_all
        @user.tracks.demo.destroy_all
        cleanup_orphan_demo_tags
        cleanup_orphan_demo_places
        demo_import.destroy
        recalc_months = cleanup_demo_stats(affected_months)
      end
    rescue StandardError => e
      Rails.logger.error("[demo] destroy failed for user #{@user.id}: #{e.class}: #{e.message}")
      return { status: :error }
    end

    enqueue_post_destroy_work(recalc_months, affected_months)

    { status: :destroyed }
  end

  def enqueue_post_destroy_work(recalc_months, affected_months)
    recalc_months.each { |year, month| Stats::CalculatingJob.perform_later(@user.id, year, month) }
    invalidate_user_caches(affected_months)
  rescue StandardError => e
    Rails.logger.error("[demo] post-destroy enqueue failed for user #{@user.id}: #{e.class}: #{e.message}")
  end

  def invalidate_user_caches(affected_months)
    affected_months.each do |year, month|
      Rails.cache.delete(Timeline::MonthSummary.cache_key_for(@user, Date.new(year, month, 1)))
    end
    Cache::InvalidateUserCaches.new(@user.id).call
  end

  private

  def demo_import
    @demo_import ||= @user.imports.find_by(demo: true)
  end

  def collect_affected_months
    quoted_tz = ActiveRecord::Base.connection.quote(user_timezone)
    year  = "EXTRACT(YEAR FROM TO_TIMESTAMP(timestamp) AT TIME ZONE #{quoted_tz})::int"
    month = "EXTRACT(MONTH FROM TO_TIMESTAMP(timestamp) AT TIME ZONE #{quoted_tz})::int"

    demo_import.points
               .pluck(Arel.sql(year), Arel.sql(month))
               .uniq
  end

  def user_timezone
    @user.safe_settings.timezone.presence || 'UTC'
  end

  def cleanup_orphan_demo_tags
    @user.tags.demo.find_each do |tag|
      next if tag.places.where(demo: false).exists?

      tag.destroy
    end
  end

  def cleanup_orphan_demo_places
    Place.demo.where(user_id: @user.id).find_each do |place|
      next if Visit.where(place_id: place.id, demo: false).exists?

      place.destroy
    end
  end

  def cleanup_demo_stats(months)
    recalc = []
    months.each do |year, month|
      stat = @user.stats.find_by(year: year, month: month)
      next unless stat

      if month_has_real_points?(year, month)
        recalc << [year, month]
      else
        stat.destroy
      end
    end
    recalc
  end

  def month_has_real_points?(year, month)
    Time.use_zone(user_timezone) do
      start_of_month = Time.zone.local(year, month, 1)
      end_of_month = start_of_month.next_month
      @user.points.where(timestamp: start_of_month.to_i...end_of_month.to_i).exists?
    end
  end
end
