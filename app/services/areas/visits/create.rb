# frozen_string_literal: true

class Areas::Visits::Create
  attr_reader :user, :areas

  def initialize(user, areas)
    @user = user
    @areas = areas
    @time_threshold_minutes = user.safe_settings.time_threshold_minutes || 30
    @merge_threshold_minutes = user.safe_settings.merge_threshold_minutes || 15
  end

  def call
    # Don't return unnecessary values, causes high memory usage (see #2119)
    areas.each { area_visits(_1) }
  end

  private

  def area_visits(area)
    months = distinct_months_for_area(area)
    Rails.logger.debug(
      '[Areas::Visits::Create] distinct_months_for_area ' \
        "area_id=#{area.id} months=#{months.inspect} count=#{months.size}"
    )

    confirmed_visit_ids = Visit.where(area_id: area.id, user_id: user.id, status: :confirmed).pluck(:id).to_set

    months.each do |month|
      points = area_points_for_month(area, month)
      visits = Visits::Group.new(
        time_threshold_minutes: @time_threshold_minutes,
        merge_threshold_minutes: @merge_threshold_minutes
      ).call(points, already_sorted: true)

      visits.each do |time_range, visit_points|
        create_or_update_visit(area, time_range, visit_points, confirmed_visit_ids)
      end
    end

    cleanup_orphaned_visits(area) if months.any?
  end

  def cleanup_orphaned_visits(area)
    Visit.where(area_id: area.id, user_id: user.id, status: :suggested)
         .where.missing(:points)
         .destroy_all
  end

  def distinct_months_for_area(area)
    area_radius =
      if user.safe_settings.distance_unit == :km
        area.radius.to_f / ::DISTANCE_UNITS[:km]
      else
        area.radius.to_f / ::DISTANCE_UNITS[user.safe_settings.distance_unit.to_sym]
      end

    relation = Point.where(user_id: user.id)
                    .where(visit_id: nil)
                    .near([area.latitude, area.longitude], area_radius, user.safe_settings.distance_unit)
    sql = <<~SQL.squish
      SELECT DISTINCT TO_CHAR(TO_TIMESTAMP(timestamp), 'YYYY-MM') AS month
      FROM (#{relation.to_sql}) AS sub
      ORDER BY month ASC
    SQL
    result = ActiveRecord::Base.connection.select_all(sql)
    result.map { |r| r['month'] }
  end

  def area_points_for_month(area, month)
    area_radius = area.radius.to_f / ::DISTANCE_UNITS[user.safe_settings.distance_unit.to_sym]

    year, month_num = month.split('-').map(&:to_i)
    month_start = Time.utc(year, month_num, 1).to_i
    month_end = (Time.utc(year, month_num, 1) + 1.month).to_i - 1

    # suggested + confirmed re-enter clustering (confirmed so they can be extended);
    # declined stay excluded. Theft guard below prevents un-merging confirmed visits.
    editable_visit_ids =
      Visit.where(area_id: area.id, user_id: user.id, status: %i[suggested confirmed]).pluck(:id)

    Point.where(user_id: user.id)
         .without_raw_data
         .near([area.latitude, area.longitude], area_radius, user.safe_settings.distance_unit)
         .where(timestamp: month_start..month_end)
         .where(visit_id: [nil, *editable_visit_ids])
         .order(timestamp: :asc)
         .to_a
  end

  def create_or_update_visit(area, time_range, visit_points, confirmed_visit_ids)
    visit = find_or_initialize_visit(area.id, visit_points.first.timestamp)

    # Theft guard: don't move a point owned by a different confirmed visit (would un-merge it).
    assignable = visit_points.reject do |p|
      confirmed_visit_ids.include?(p.visit_id) && p.visit_id != visit.id
    end
    return if assignable.empty?

    Rails.logger.info("Visit from #{time_range}, Points: #{assignable.size}")

    ActiveRecord::Base.transaction do
      group_ended_at = Time.zone.at(assignable.last.timestamp)

      visit.tap do |v|
        # Grow-only: never shrink a visit that already spans past this group.
        v.ended_at = v.ended_at && v.ended_at > group_ended_at ? v.ended_at : group_ended_at
        v.duration = ((v.ended_at.to_i - v.started_at.to_i) / 60)
        if v.new_record?
          v.name = "#{area.name}, #{time_range}"
          v.status = :suggested
        end
      end

      visit.save!

      Point.where(id: assignable.map(&:id)).update_all(visit_id: visit.id)
    end
  end

  def find_or_initialize_visit(area_id, timestamp)
    Visit.find_or_initialize_by(
      area_id:,
      user_id: user.id,
      started_at: Time.zone.at(timestamp)
    )
  end
end
