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

    redirect_target = timeline_map_url(date: params[:date].presence || 'today', status: source_status)

    if result
      redirect_to redirect_target,
                  notice: "#{result[:count]} #{'visit'.pluralize(result[:count])} #{status}."
    else
      redirect_to redirect_target, alert: 'Failed to update visits.'
    end
  end

  def update
    params_to_update = visit_params.to_h
    params_to_update.delete(:name) if params_to_update[:name].is_a?(String) && params_to_update[:name].strip.empty?

    @affected_started_at = [@visit.started_at]

    update_visit_name_from_place if params_to_update[:place_id].present?
    auto_name_on_confirm if confirming_suggested_visit?(params_to_update)

    if @visit.update(params_to_update)
      respond_to do |format|
        format.turbo_stream do
          streams = if @visit.saved_change_to_status?
                      [
                        turbo_stream.remove("visit_item_#{@visit.id}"),
                        stream_flash(:notice, "Visit #{@visit.status}.")
                      ]
                    else
                      [
                        turbo_stream.replace("visit_name_#{@visit.id}",
                                             partial: 'visits/name', locals: { visit: @visit }),
                        turbo_stream.replace("visit_buttons_#{@visit.id}",
                                             partial: 'visits/buttons', locals: { visit: @visit }),
                        stream_flash(:notice, 'Visit updated.')
                      ]
                    end
          render turbo_stream: streams
        end
        format.html { redirect_back(fallback_location: timeline_map_url(date: 'today', status: 'suggested')) }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace("visit_name_#{@visit.id}",
                                 partial: 'visits/name', locals: { visit: @visit }),
            turbo_stream.replace("visit_buttons_#{@visit.id}",
                                 partial: 'visits/buttons', locals: { visit: @visit }),
            stream_flash(:error, 'Failed to update visit.')
          ]
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
      format.html { redirect_to timeline_map_url(date: 'today'), status: :see_other }
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

  def timeline_map_url(date: 'today', status: nil)
    params = { panel: 'timeline', date: date }
    params[:status] = status if status.present?
    "/map/v2?#{params.to_query}"
  end

  def update_visit_name_from_place
    place = current_user.places.find_by(id: visit_params[:place_id])
    @visit.name = place.name if place
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

  def bust_timeline_month_cache
    started_ats = Array(@affected_started_at).compact
    return if started_ats.empty?

    started_ats.map(&:to_date).map(&:beginning_of_month).uniq.each do |month_start|
      Rails.cache.delete(Timeline::MonthSummary.cache_key_for(current_user, month_start))
    end
  end
end
