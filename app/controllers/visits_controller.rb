# frozen_string_literal: true

class VisitsController < ApplicationController
  include FlashStreamable

  before_action :authenticate_user!
  before_action :set_visit, only: %i[update destroy]
  after_action :bust_timeline_month_cache, only: %i[update bulk_update destroy]

  def bulk_update
    status = params[:status]
    source_status = params[:source_status] || 'suggested'

    scope = current_user.scoped_visits.where(status: source_status)
    scope = apply_date_scope(scope) if params[:date].present?

    @affected_started_at = scope.pluck(:started_at)
    visit_ids = scope.pluck(:id)

    result = Visits::BulkUpdate.new(current_user, visit_ids, status).call
    redirect_target = build_timeline_url(date: params[:date].presence || 'today', status: source_status)

    if result
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: build_bulk_update_streams(status, result[:count])
        end
        format.html do
          redirect_to redirect_target,
                      notice: "#{result[:count]} #{'visit'.pluralize(result[:count])} #{status}."
        end
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: stream_flash(:error, 'Failed to update visits.')
        end
        format.html { redirect_to redirect_target, alert: 'Failed to update visits.' }
      end
    end
  end

  def update
    params_to_update = visit_params.to_h
    params_to_update.delete(:name) if params_to_update[:name].is_a?(String) && params_to_update[:name].strip.empty?

    # Cross-tenant IDOR guard: place_id must belong to current_user.
    # Suggested places (visit.suggested_places) are also acceptable since
    # they're already user-scoped via the visit relationship.
    if params_to_update[:place_id].present?
      allowed_place_ids = current_user.places.where(id: params_to_update[:place_id]).pluck(:id) +
                          @visit.suggested_places.where(id: params_to_update[:place_id]).pluck(:id)
      return render_unprocessable('Invalid place') unless allowed_place_ids.include?(params_to_update[:place_id].to_i)
    end

    # Capture both old and new month so cache busts cover edits that move
    # a visit across month boundaries.
    @affected_started_at = [@visit.started_at]
    if params_to_update[:started_at].present?
      new_started_at = parse_time_safely(params_to_update[:started_at])
      @affected_started_at << new_started_at if new_started_at
    end

    if params_to_update[:place_id].present?
      update_visit_name_from_place(params_to_update[:place_id])
    elsif confirming_suggested_visit?(params_to_update)
      # Only auto-pick from the visit's first suggested place when the
      # user did NOT explicitly select one — otherwise we'd overwrite the
      # name the picker just set.
      auto_name_on_confirm
    end

    if @visit.update(params_to_update)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: build_update_streams
        end
        format.html { redirect_back(fallback_location: build_timeline_url(date: 'today', status: 'suggested')) }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: stream_flash(:error, 'Failed to update visit.')
        end
        format.html { render :edit, status: :unprocessable_content }
      end
    end
  end

  def destroy
    @affected_started_at = [@visit.started_at]
    @visit.destroy!

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.remove("visit_item_#{@visit.id}")
      end
      format.html { redirect_to build_timeline_url(date: 'today'), status: :see_other }
    end
  end

  private

  def set_visit
    @visit = current_user.visits.find(params[:id])
  end

  def apply_date_scope(scope)
    tz = current_user.safe_settings.timezone.presence || 'UTC'
    range = Date.parse(params[:date]).in_time_zone(tz).all_day
    scope.where(started_at: range)
  end

  # Builds the timeline-entry hash for a single visit — lets the update
  # turbo_stream re-render `_visit_entry.html.erb` with fresh status / name /
  # place / suggested_places data. Reuses Timeline::DayAssembler to keep the
  # payload shape consistent with the day-level fetch.
  def timeline_entry_for(visit)
    Timeline::DayAssembler.new(current_user, start_at: '', end_at: '')
                          .build_visit_entry(visit)
  end

  # Turbo streams for #bulk_update: swaps the day's visit-list contents with
  # a freshly-assembled day (so every row's status is current), refreshes the
  # three filter counts in the rail, and shows the "N visits confirmed." flash.
  # `turbo_stream.update` targets the frame's children — we keep the frame
  # element (its id + Stimulus target) intact.
  def build_bulk_update_streams(status, count)
    tz = current_user.safe_settings.timezone.presence || 'UTC'
    date_str = params[:date].presence || Time.use_zone(tz) { Date.current.to_s }
    day_range = Time.use_zone(tz) { Date.parse(date_str).in_time_zone.all_day }

    days = Timeline::DayAssembler.new(
      current_user,
      start_at: day_range.begin.iso8601,
      end_at: day_range.end.iso8601,
      distance_unit: current_user.safe_settings.distance_unit
    ).call
    day = days.first

    # Filter pills are scoped to the calendar's currently-visible month, so
    # the streamed counts must be too — otherwise after a bulk action the
    # pills swap from a monthly count to an all-time count and look wrong.
    status_counts = month_status_counts(date_str)

    streams = []
    streams << if day
                 turbo_stream.update('timeline-feed-frame',
                                     partial: 'map/timeline_feeds/day',
                                     locals: { day: day })
               else
                 turbo_stream.update('timeline-feed-frame', '')
               end
    streams << turbo_stream.replace('filter-count-confirmed',
                                    partial: 'map/timeline_feeds/filter_count',
                                    locals: { status: 'confirmed', count: status_counts['confirmed'].to_i })
    streams << turbo_stream.replace('filter-count-suggested',
                                    partial: 'map/timeline_feeds/filter_count',
                                    locals: { status: 'suggested', count: status_counts['suggested'].to_i })
    streams << turbo_stream.replace('filter-count-declined',
                                    partial: 'map/timeline_feeds/filter_count',
                                    locals: { status: 'declined', count: status_counts['declined'].to_i })
    streams << stream_flash(:notice, "#{count} #{'visit'.pluralize(count)} #{status}.")
    streams
  end

  # Turbo streams emitted on a successful #update:
  #   - Replace the visit row (status dot, picker, tags, everything)
  #   - Re-render the day's suggestion banner (disappears when count hits 0)
  #   - Re-render the three rail filter-count badges (confirmed/suggested/declined)
  # Keeps the panel's state consistent after any confirm/decline/rename.
  def build_update_streams
    tz = current_user.safe_settings.timezone.presence || 'UTC'
    day_date = Time.use_zone(tz) { @visit.started_at.in_time_zone.to_date.to_s }
    day_range = Time.use_zone(tz) { Date.parse(day_date).in_time_zone.all_day }

    day_suggested_count = current_user.scoped_visits
                                      .where(started_at: day_range, status: :suggested)
                                      .count
    # Match the FILTER pills' month-scoped counts — they would otherwise
    # flip from monthly (initial render) to all-time (after an edit).
    status_counts = month_status_counts(day_date)

    [
      turbo_stream.replace("visit_entry_#{@visit.id}",
                           partial: 'map/timeline_feeds/visit_entry',
                           locals: { entry: timeline_entry_for(@visit) }),
      turbo_stream.replace("day-banner-#{day_date}",
                           partial: 'map/timeline_feeds/day_banner',
                           locals: { date: day_date, suggested_count: day_suggested_count }),
      turbo_stream.replace('filter-count-confirmed',
                           partial: 'map/timeline_feeds/filter_count',
                           locals: { status: 'confirmed', count: status_counts['confirmed'].to_i }),
      turbo_stream.replace('filter-count-suggested',
                           partial: 'map/timeline_feeds/filter_count',
                           locals: { status: 'suggested', count: status_counts['suggested'].to_i }),
      turbo_stream.replace('filter-count-declined',
                           partial: 'map/timeline_feeds/filter_count',
                           locals: { status: 'declined', count: status_counts['declined'].to_i }),
      stream_flash(:notice, "Visit #{@visit.status}.")
    ]
  end

  def build_timeline_url(date: 'today', status: nil)
    params = { panel: 'timeline', date: date }
    params[:status] = status if status.present?
    "/map/v2?#{params.to_query}"
  end

  # Visits-by-status counts scoped to the month containing `date_str`. Used by
  # the FILTER pills, which are intentionally month-bound so users see "this
  # month's" totals next to the calendar grid.
  def month_status_counts(date_str)
    tz = current_user.safe_settings.timezone.presence || 'UTC'
    month_range = Time.use_zone(tz) { Date.parse(date_str).in_time_zone.all_month }
    current_user.scoped_visits
                .where(started_at: month_range)
                .group(:status)
                .count
  end

  # Look up the place across both user-owned places AND the visit's
  # suggested_places. Suggested places may have a NULL user_id (the
  # `Place.user_id` column is optional, populated for user-created
  # places only) and would otherwise miss `current_user.places`.
  def update_visit_name_from_place(place_id)
    place = current_user.places.find_by(id: place_id) ||
            @visit.suggested_places.find_by(id: place_id)
    @visit.name = place.name if place && place.name.present?
  end

  def confirming_suggested_visit?(params_to_update = visit_params)
    params_to_update[:status] == 'confirmed' && @visit.suggested? && params_to_update[:name].blank?
  end

  def auto_name_on_confirm
    place = @visit.place || @visit.suggested_places.first
    @visit.name = place.name if place&.name.present?
  end

  def visit_params
    params.require(:visit).permit(:name, :place_id, :started_at, :ended_at, :status)
  end

  def render_unprocessable(message)
    respond_to do |format|
      format.turbo_stream { render turbo_stream: stream_flash(:error, message), status: :unprocessable_content }
      format.html { redirect_back(fallback_location: build_timeline_url, alert: message) }
    end
  end

  def parse_time_safely(value)
    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def bust_timeline_month_cache
    started_ats = Array(@affected_started_at).compact
    return if started_ats.empty?

    tz = current_user.safe_settings.timezone.presence || 'UTC'
    Time.use_zone(tz) do
      started_ats.map { |t| t.in_time_zone.to_date.beginning_of_month }.uniq.each do |month_start|
        Rails.cache.delete(Timeline::MonthSummary.cache_key_for(current_user, month_start))
      end
    end
  end
end
