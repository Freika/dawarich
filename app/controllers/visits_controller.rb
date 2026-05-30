# frozen_string_literal: true

class VisitsController < ApplicationController
  include FlashStreamable

  MAX_BULK_VISIT_IDS = Visits::BulkDestroy::MAX_VISIT_IDS

  before_action :authenticate_user!
  before_action :set_visit, only: %i[update destroy]
  after_action :bust_timeline_month_cache, only: %i[update bulk_update bulk_destroy destroy merge]

  def bulk_update
    status = params[:status]
    source_status = params[:source_status] || 'suggested'
    explicit_visit_ids = parse_visit_ids(params[:visit_ids])

    if explicit_visit_ids.any?
      return render_unprocessable(too_many_visits_message) if explicit_visit_ids.length > MAX_BULK_VISIT_IDS

      scope = current_user.scoped_visits.where(id: explicit_visit_ids)
      if scope.count != explicit_visit_ids.length
        return render_not_found(message_for_missing_visits(explicit_visit_ids))
      end
    else
      scope = current_user.scoped_visits.where(status: source_status)
      scope = apply_date_scope(scope) if params[:date].present?
      return render_unprocessable(too_many_visits_message) if scope.count > MAX_BULK_VISIT_IDS
    end

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

  def bulk_destroy
    visit_ids = parse_visit_ids(params[:visit_ids])
    return render_unprocessable('Select at least one visit to delete.') if visit_ids.empty?
    return render_unprocessable(too_many_visits_message) if visit_ids.length > MAX_BULK_VISIT_IDS

    visits = current_user.scoped_visits.where(id: visit_ids)
    return render_not_found(message_for_missing_visits(visit_ids)) if visits.count != visit_ids.length

    @affected_started_at = visits.pluck(:started_at)

    service = Visits::BulkDestroy.new(current_user, visit_ids)
    result = service.call

    if result
      respond_to do |format|
        format.turbo_stream { render turbo_stream: build_bulk_destroy_streams(result[:count]) }
        format.html do
          redirect_back(fallback_location: build_timeline_url(date: 'today'),
                        notice: bulk_destroy_success_message(result[:count]),
                        status: :see_other)
        end
      end
    else
      render_unprocessable(service.errors.join(', ').presence || 'Failed to delete visits.')
    end
  end

  def update
    params_to_update = visit_params.to_h
    params_to_update.delete(:name) if params_to_update[:name].is_a?(String) && params_to_update[:name].strip.empty?

    auto_confirm_result = maybe_auto_confirm_with_user_place!(params_to_update)
    return render_unprocessable('Could not save the typed name as a place.') if auto_confirm_result == :place_invalid

    if params_to_update[:place_id].present?
      raw_place_id = params_to_update[:place_id]
      allowed = current_user.places.where(id: raw_place_id).exists? ||
                @visit.suggested_places.where(id: raw_place_id).exists?
      return render_unprocessable('Invalid place') unless allowed
    end

    selected_area = nil
    if params_to_update[:area_id].present?
      selected_area = current_user.areas.find_by(id: params_to_update[:area_id])
      return render_unprocessable('Invalid area') unless selected_area
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
    elsif selected_area
      @visit.name = selected_area.name if selected_area.name.present?
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
        render turbo_stream: [
          turbo_stream.remove("visit_item_#{@visit.id}"),
          suggestions_badge_stream
        ]
      end
      format.html { redirect_to build_timeline_url(date: 'today'), status: :see_other }
    end
  end

  def merge
    visit_ids = parse_visit_ids(params[:visit_ids])
    return render_unprocessable('Select at least 2 visits to merge.') if visit_ids.length < 2

    visits = current_user.scoped_visits.where(id: visit_ids).order(:started_at)
    return render_not_found(message_for_missing_visits(visit_ids)) if visits.length != visit_ids.length

    return render_unprocessable('Visits must be on the same day.') unless same_day?(visits)

    @affected_started_at = visits.map(&:started_at)

    service = Visits::MergeService.new(visits)
    merged = service.call

    if merged&.persisted?
      respond_to do |format|
        format.turbo_stream { render turbo_stream: build_merge_streams(merged) }
        format.html { redirect_back(fallback_location: build_timeline_url(date: 'today')) }
      end
    else
      render_unprocessable(service.errors.join(', ').presence || 'Failed to merge visits.')
    end
  end

  private

  def set_visit
    @visit = current_user.scoped_visits.find(params[:id])
  end

  def parse_visit_ids(raw)
    Array(raw).map(&:to_i).reject(&:zero?).uniq
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
    streams << suggestions_badge_stream
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
      suggestions_badge_stream,
      stream_flash(:notice, "Visit #{@visit.status}.")
    ]
  end

  def build_timeline_url(date: 'today', status: nil)
    params = { panel: 'timeline', date: date }
    params[:status] = status if status.present?
    "/map/v2?#{params.to_query}"
  end

  # Refreshes the lifetime pending-suggestion badge on the Timeline map button
  # so it doesn't go stale after a confirm/decline/merge/delete (it would
  # otherwise keep the count from the initial page render).
  def suggestions_badge_stream
    turbo_stream.replace('timeline-suggestions-badge',
                         partial: 'map/timeline_feeds/suggestions_badge',
                         locals: { count: current_user.scoped_visits.suggested.count })
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

  def update_visit_name_from_place(place_id)
    place = current_user.places.find_by(id: place_id) ||
            @visit.suggested_places.find_by(id: place_id)
    @visit.name = place.name if place && place.name.present?
  end

  def confirming_suggested_visit?(params_to_update = visit_params)
    params_to_update[:status] == 'confirmed' && @visit.suggested? && params_to_update[:name].blank?
  end

  PLACE_NAME_MAX_LENGTH = 200

  def maybe_auto_confirm_with_user_place!(params_to_update)
    return :noop unless @visit.suggested?
    return :noop if params_to_update[:place_id].present?
    return :noop if params_to_update[:status].present? && params_to_update[:status] != 'suggested'

    name = params_to_update[:name].to_s.strip
    return :noop if name.blank?

    name = name[0, PLACE_NAME_MAX_LENGTH]
    params_to_update[:name] = name

    place = find_or_create_user_place_for_rename(name)
    return :place_invalid unless place

    params_to_update[:place_id] = place.id
    params_to_update[:status] = 'confirmed'
    :auto_confirmed
  end

  def find_or_create_user_place_for_rename(name)
    lat, lon = @visit.center
    return nil if lat.blank? || lon.blank?
    return nil if lat.to_f.zero? && lon.to_f.zero?

    existing = current_user.places.where(name: name).near([lat, lon], 50, :m).first
    return existing if existing

    current_user.places.create!(
      name: name,
      latitude: lat,
      longitude: lon,
      source: :manual
    )
  rescue ActiveRecord::RecordInvalid
    nil
  end

  def auto_name_on_confirm
    place = @visit.place || @visit.suggested_places.first
    @visit.name = place.name if place&.name.present?
  end

  def visit_params
    params.require(:visit).permit(:name, :place_id, :area_id, :started_at, :ended_at, :status)
  end

  def same_day?(visits)
    tz = current_user.safe_settings.timezone.presence || 'UTC'
    Time.use_zone(tz) do
      visits.map { |v| v.started_at.in_time_zone.to_date }.uniq.length == 1
    end
  end

  def render_not_found(message)
    respond_to do |format|
      format.turbo_stream { render turbo_stream: stream_flash(:error, message), status: :not_found }
      format.html { redirect_back(fallback_location: build_timeline_url, alert: message) }
    end
  end

  def build_merge_streams(merged)
    tz = current_user.safe_settings.timezone.presence || 'UTC'
    day_date = Time.use_zone(tz) { merged.started_at.in_time_zone.to_date.to_s }
    day_range = Time.use_zone(tz) { Date.parse(day_date).in_time_zone.all_day }

    days = Timeline::DayAssembler.new(
      current_user,
      start_at: day_range.begin.iso8601,
      end_at: day_range.end.iso8601,
      distance_unit: current_user.safe_settings.distance_unit
    ).call
    day = days.first

    status_counts = month_status_counts(day_date)

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
    streams << suggestions_badge_stream
    streams << stream_flash(:notice, 'Visits merged.')
    streams
  end

  def build_bulk_destroy_streams(count)
    tz = current_user.safe_settings.timezone.presence || 'UTC'
    affected_dates = Time.use_zone(tz) do
      Array(@affected_started_at).compact.map { |t| t.in_time_zone.to_date }.uniq
    end
    visible_date = affected_dates.first if affected_dates.length == 1
    counts_date_str = (visible_date || Time.use_zone(tz) { Date.current }).to_s

    streams = []
    day_stream = build_day_frame_stream(visible_date, tz)
    streams << day_stream if day_stream
    streams.concat(filter_count_streams(counts_date_str))
    streams << suggestions_badge_stream
    streams << stream_flash(:notice, bulk_destroy_success_message(count))
    streams
  end

  # When all deleted visits fall on the same user-local date, we can rebuild
  # that day's frame from fresh data. For cross-day deletions (e.g. via API),
  # we leave the frame alone — the controller can't know which day the user
  # is currently viewing.
  def build_day_frame_stream(date, time_zone)
    return nil unless date

    day_range = Time.use_zone(time_zone) { date.in_time_zone.all_day }
    day = Timeline::DayAssembler.new(
      current_user,
      start_at: day_range.begin.iso8601,
      end_at: day_range.end.iso8601,
      distance_unit: current_user.safe_settings.distance_unit
    ).call.first

    if day
      turbo_stream.update('timeline-feed-frame',
                          partial: 'map/timeline_feeds/day',
                          locals: { day: day })
    else
      turbo_stream.update('timeline-feed-frame', '')
    end
  end

  def filter_count_streams(date_str)
    status_counts = month_status_counts(date_str)
    %w[confirmed suggested declined].map do |status|
      turbo_stream.replace("filter-count-#{status}",
                           partial: 'map/timeline_feeds/filter_count',
                           locals: { status: status, count: status_counts[status].to_i })
    end
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

  def too_many_visits_message
    "You can update up to #{MAX_BULK_VISIT_IDS} visits at once. Narrow your selection and try again."
  end

  def message_for_missing_visits(ids)
    return missing_visits_message unless current_user.plan_restricted?

    archived_count = current_user.visits.where(id: ids)
                                 .where('started_at < ?', current_user.data_window_start)
                                 .count
    return missing_visits_message if archived_count.zero?

    plan_window_visits_message
  end

  def missing_visits_message
    "Some of those visits aren't here anymore — probably edited in another tab. Refresh and try again."
  end

  def plan_window_visits_message
    "Some of those visits are outside your Lite plan's 12-month window. Upgrade to Pro to manage older data."
  end

  def bulk_destroy_success_message(count)
    noun = 'visit'.pluralize(count)
    "#{count} #{noun} removed. Your location points are still here."
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
