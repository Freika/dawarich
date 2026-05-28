# frozen_string_literal: true

class DemoData::Importer
  def initialize(user)
    @user = user
  end

  def call
    return { status: :exists } if @user.imports.exists?(demo: true)

    anchor = user_local_beginning_of_day
    import = nil

    begin
      ActiveRecord::Base.transaction do
        import = create_marker_import
        DemoData::PointsSeeder.new(@user, import, anchor).call
        DemoData::DerivativesSeeder.new(@user, anchor, import: import).call
      end
    rescue StandardError => e
      Rails.logger.error("[demo] seed failed for user #{@user.id}: #{e.class}: #{e.message}")
      return { status: :error }
    end

    invalidate_caches_safely(import)

    { status: :created }
  end

  private

  def create_marker_import
    @user.imports.create!(
      name: 'Demo Data (Berlin + Prague)',
      source: :geojson,
      demo: true,
      status: :completed,
      processing_started_at: Time.current,
      skip_background_processing: true
    )
  end

  def user_local_beginning_of_day
    tz = @user.safe_settings.timezone.presence || 'UTC'
    Time.use_zone(tz) { Time.zone.now.beginning_of_day }
  end

  def invalidate_caches_safely(import)
    months_from_import(import).each do |year, month|
      Rails.cache.delete(Timeline::MonthSummary.cache_key_for(@user, Date.new(year, month, 1)))
    end
    Cache::InvalidateUserCaches.new(@user.id).call
  rescue StandardError => e
    Rails.logger.error("[demo] cache invalidation failed for user #{@user.id}: #{e.class}: #{e.message}")
  end

  def months_from_import(import)
    tz = @user.safe_settings.timezone.presence || 'UTC'
    quoted_tz = ActiveRecord::Base.connection.quote(tz)
    year  = "EXTRACT(YEAR FROM TO_TIMESTAMP(timestamp) AT TIME ZONE #{quoted_tz})::int"
    month = "EXTRACT(MONTH FROM TO_TIMESTAMP(timestamp) AT TIME ZONE #{quoted_tz})::int"

    import.points.pluck(Arel.sql(year), Arel.sql(month)).uniq
  end
end
