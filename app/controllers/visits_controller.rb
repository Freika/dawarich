# frozen_string_literal: true

class VisitsController < ApplicationController
  include FlashStreamable

  MAX_BULK_VISIT_IDS = Visits::BulkDestroy::MAX_VISIT_IDS
  ALLOWED_SOURCE_STATUSES = %w[suggested].freeze

  before_action :authenticate_user!
  before_action :set_visit, only: %i[update destroy]
  before_action :reject_unknown_source_status, only: %i[bulk_update bulk_destroy]

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
                      notice: bulk_update_success_message(status, result[:count])
        end
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: stream_flash(:error, I18n.t('controllers.visits.failed_to_update_visits'))
        end
        format.html { redirect_to redirect_target, alert: I18n.t('controllers.visits.failed_to_update_visits') }
      end
    end
  end

  def bulk_destroy
    explicit_visit_ids = parse_visit_ids(params[:visit_ids])

    if explicit_visit_ids.any?
      return render_unprocessable(too_many_visits_message) if explicit_visit_ids.length > MAX_BULK_VISIT_IDS

      visits = current_user.scoped_visits.where(id: explicit_visit_ids)
      if visits.count != explicit_visit_ids.length
        return render_not_found(message_for_missing_visits(explicit_visit_ids))
      end

      visit_ids = explicit_visit_ids
    elsif params[:date].present? && params[:source_status].present?
      source_status = params[:source_status]
      scope = current_user.scoped_visits.where(status: source_status)
      scope = apply_date_scope(scope)
      return render_unprocessable(too_many_visits_message) if scope.count > MAX_BULK_VISIT_IDS

      visit_ids = scope.pluck(:id)
      return render_unprocessable(I18n.t('controllers.visits.no_matching_visits')) if visit_ids.empty?
    else
      return render_unprocessable(I18n.t('controllers.visits.select_visit_to_delete'))
    end

    service = Visits::BulkDestroy.new(current_user, visit_ids)
    result = service.call

    if result
      respond_to do |format|
        format.turbo_stream { render turbo_stream: build_bulk_destroy_streams(result) }
        format.html do
          redirect_back(fallback_location: build_timeline_url(date: 'today'),
                        notice: bulk_destroy_success_message(result[:count]),
                        status: :see_other)
        end
      end
    else
      render_unprocessable(service.errors.join(', ').presence || I18n.t('controllers.visits.failed_to_delete_visits'))
    end
  end

  def update
    params_to_update = visit_params.to_h
    if params_to_update[:name].is_a?(String)
      stripped = params_to_update[:name].strip
      params_to_update[:name] = stripped.empty? ? nil : stripped
    end

    params_to_update = Visits::ResolvePlaceSelection.new(current_user, visit: @visit).call(params_to_update)

    if params_to_update[:place_id].present?
      update_visit_label_from_place(params_to_update[:place_id])
    elsif confirming_suggested_visit?(params_to_update)
      # Only auto-pick from the visit's first suggested place when the
      # user did NOT explicitly select one — otherwise we'd overwrite the
      # name the picker just set.
      auto_name_on_confirm
    end

    # Editing a suggested visit is an assertion that it happened — confirm
    # it silently unless the request set a status itself (e.g. decline).
    params_to_update[:status] = 'confirmed' if @visit.suggested? && params_to_update[:status].blank?

    if @visit.update(params_to_update)
      @visit.adopt! unless @visit.status == 'declined'
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: build_update_streams
        end
        format.html { redirect_back(fallback_location: build_timeline_url(date: 'today', status: 'suggested')) }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: stream_flash(:error, I18n.t('controllers.visits.failed_to_update_visit'))
        end
        format.html do
          redirect_back(fallback_location: build_timeline_url(date: 'today'),
                        alert: I18n.t('controllers.visits.failed_to_update_visit'))
        end
      end
    end
  rescue Visits::ResolvePlaceSelection::Invalid => e
    render_unprocessable(I18n.t("controllers.visits.#{e.reason}"))
  end

  def destroy
    # Soft delete: the row stays as a tombstone so visit detection never
    # re-suggests it; the user's points are untouched either way.
    @visit.soft_delete!

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: build_destroy_streams
      end
      format.html { redirect_to build_timeline_url(date: 'today'), status: :see_other }
    end
  end

  def merge
    visit_ids = parse_visit_ids(params[:visit_ids])
    return render_unprocessable(I18n.t('controllers.visits.select_visits_to_merge')) if visit_ids.length < 2

    visits = current_user.scoped_visits.where(id: visit_ids).order(:started_at)
    return render_not_found(message_for_missing_visits(visit_ids)) if visits.length != visit_ids.length

    return render_unprocessable(I18n.t('controllers.visits.visits_must_share_day')) unless same_day?(visits)

    service = Visits::MergeService.new(visits)
    merged = service.call

    if merged&.persisted?
      respond_to do |format|
        format.turbo_stream { render turbo_stream: build_merge_streams(merged) }
        format.html { redirect_back(fallback_location: build_timeline_url(date: 'today')) }
      end
    else
      render_unprocessable(service.errors.join(', ').presence || I18n.t('controllers.visits.failed_to_merge_visits'))
    end
  end

  private

  def reject_unknown_source_status
    return if params[:source_status].blank?
    return if ALLOWED_SOURCE_STATUSES.include?(params[:source_status].to_s)

    render_unprocessable(I18n.t('controllers.visits.unsupported_source_status'))
  end

  def set_visit
    @visit = current_user.scoped_visits.find(params[:id])
  end

  def parse_visit_ids(raw)
    Array(raw).map(&:to_i).reject(&:zero?).uniq
  end

  # Visits shown on the day: those that started on it and those still going
  # on from an earlier day, matching Timeline::DayAssembler.
  def apply_date_scope(scope)
    range = Date.parse(params[:date]).in_time_zone(current_user.timezone_or_utc).all_day
    scope.overlapping(range.begin, range.end)
  end

  def viewed_date
    Date.iso8601(params[:date].to_s) if params[:date].present?
  rescue Date::Error
    nil
  end

  # Builds the timeline-entry hash for a single visit — lets the update
  # turbo_stream re-render `_visit_entry.html.erb` with fresh status / name /
  # place / suggested_places data. Reuses Timeline::DayAssembler to keep the
  # payload shape consistent with the day-level fetch.
  def timeline_entry_for(visit)
    Timeline::DayAssembler.new(current_user, privacy_zone_masker: current_privacy_zone_masker)
                          .build_visit_entry(visit, date: viewed_date)
  end

  # Turbo streams for #bulk_update: swaps the day's visit-list contents with
  # a freshly-assembled day (so every row's state is current) and shows the
  # "N visits confirmed." flash. `turbo_stream.update` targets the frame's
  # children — we keep the frame element (its id + Stimulus target) intact.
  def build_bulk_update_streams(status, count)
    date_str = params[:date].presence || Time.use_zone(current_user.timezone_or_utc) { Date.current.to_s }

    [
      day_frame_stream(Date.parse(date_str)),
      stream_flash(:notice, bulk_update_success_message(status, count))
    ]
  end

  def local_date(time)
    time.in_time_zone(current_user.timezone_or_utc).to_date
  end

  def day_frame_stream(date)
    day_range = Time.use_zone(current_user.timezone_or_utc) { date.in_time_zone.all_day }
    day = Timeline::DayAssembler.new(
      current_user,
      start_at: day_range.begin.iso8601,
      end_at: day_range.end.iso8601,
      distance_unit: current_user.safe_settings.distance_unit,
      privacy_zone_masker: current_privacy_zone_masker
    ).call.first
    return turbo_stream.update('timeline-feed-frame', '') unless day

    turbo_stream.update('timeline-feed-frame', partial: 'map/timeline_feeds/day', locals: { day: day })
  end

  # Turbo streams emitted on a successful #update: replace the visit row
  # (name, picker, tags, everything). The period picker's calendar refetches
  # its month when the row changes.
  def build_update_streams
    [
      turbo_stream.replace("visit_entry_#{@visit.id}",
                           partial: 'map/timeline_feeds/visit_entry',
                           locals: { entry: timeline_entry_for(@visit) }),
      stream_flash(
        :notice,
        I18n.t("controllers.visits.visit_updated.#{@visit.status}")
      )
    ]
  end

  def build_timeline_url(date: 'today', status: nil)
    params = { panel: 'timeline', date: date }
    params[:status] = status if status.present?
    "/map/v2?#{params.to_query}"
  end

  def update_visit_label_from_place(place_id)
    place = current_user.places.find_by(id: place_id) ||
            @visit.suggested_places.find_by(id: place_id)
    return unless place

    @visit.clear_echoed_name
    @visit.location_label = place.name if place.name.present?
  end

  def confirming_suggested_visit?(params_to_update = visit_params)
    params_to_update[:status] == 'confirmed' && @visit.suggested? && params_to_update[:name].blank?
  end

  def auto_name_on_confirm
    place = @visit.place || @visit.suggested_places.first
    @visit.location_label = place.name if place&.name.present?
  end

  def visit_params
    params.require(:visit).permit(:name, :place_id, :area_id, :started_at, :ended_at, :status)
  end

  def same_day?(visits)
    visits.map { |v| Timeline::TrackDayShares.shares_between(v.started_at, v.ended_at, current_user.timezone_or_utc).keys }
          .reduce(:&).any?
  end

  def render_not_found(message)
    respond_to do |format|
      format.turbo_stream { render turbo_stream: stream_flash(:error, message), status: :not_found }
      format.html { redirect_back(fallback_location: build_timeline_url, alert: message) }
    end
  end

  def build_merge_streams(merged)
    [
      day_frame_stream(viewed_date || local_date(merged.started_at)),
      stream_flash(:notice, I18n.t('controllers.visits.visits_merged'))
    ]
  end

  def build_destroy_streams
    [
      turbo_stream.remove("visit_entry_#{@visit.id}"),
      stream_flash(:notice, I18n.t('controllers.visits.visit_removed'))
    ]
  end

  # When all deleted visits fall on the same user-local date, we can rebuild
  # that day's frame from fresh data. For cross-day deletions (e.g. via API),
  # we leave the frame alone — the controller can't know which day the user
  # is currently viewing.
  def build_bulk_destroy_streams(result)
    affected_dates = result[:started_ats].map { |time| local_date(time) }.uniq
    visible_date = viewed_date || (affected_dates.first if affected_dates.one?)

    [
      (day_frame_stream(visible_date) if visible_date),
      stream_flash(:notice, bulk_destroy_success_message(result[:count]))
    ].compact
  end

  def render_unprocessable(message)
    respond_to do |format|
      format.turbo_stream { render turbo_stream: stream_flash(:error, message), status: :unprocessable_content }
      format.html { redirect_back(fallback_location: build_timeline_url, alert: message) }
    end
  end

  def too_many_visits_message
    I18n.t('controllers.visits.too_many_visits', count: MAX_BULK_VISIT_IDS)
  end

  def message_for_missing_visits(ids)
    window_start = current_user.data_window_start
    return missing_visits_message unless window_start

    archived_count = current_user.visits.where(id: ids)
                                 .where('started_at < ?', window_start)
                                 .count
    return missing_visits_message if archived_count.zero?

    plan_window_visits_message
  end

  def missing_visits_message
    I18n.t('controllers.visits.missing_visits')
  end

  def plan_window_visits_message
    I18n.t('controllers.visits.plan_window_visits')
  end

  def bulk_destroy_success_message(count)
    I18n.t('controllers.visits.bulk_removed', count:)
  end

  def bulk_update_success_message(status, count)
    I18n.t("controllers.visits.bulk_updated.#{status}", count:)
  end
end
