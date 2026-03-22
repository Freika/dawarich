# frozen_string_literal: true

class VisitsController < ApplicationController
  include FlashStreamable

  before_action :authenticate_user!
  before_action :set_visit, only: %i[update]

  def index
    order_by = params[:order_by] || 'asc'
    status   = params[:status]   || 'confirmed'

    visits = current_user
             .scoped_visits
             .where(status:)
             .includes(%i[suggested_places area points place])
             .order(started_at: order_by)

    @suggested_visits_count = current_user.scoped_visits.suggested.count
    @visits = visits.page(params[:page]).per(10)
  end

  def bulk_update
    status = params[:status]
    source_status = params[:source_status] || 'suggested'
    visit_ids = current_user.scoped_visits.where(status: source_status).pluck(:id)

    result = Visits::BulkUpdate.new(current_user, visit_ids, status).call

    if result
      redirect_to visits_path(status: source_status),
                  notice: "#{result[:count]} #{'visit'.pluralize(result[:count])} #{status}."
    else
      redirect_to visits_path(status: source_status), alert: 'Failed to update visits.'
    end
  end

  def update
    update_visit_name_from_place if visit_params[:place_id].present?

    if @visit.update(visit_params)
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
        format.html { redirect_back(fallback_location: visits_path(status: :suggested)) }
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

  private

  def set_visit
    @visit = current_user.visits.find(params[:id])
  end

  def update_visit_name_from_place
    place = current_user.places.find_by(id: visit_params[:place_id])
    @visit.name = place.name if place
  end

  def visit_params
    params.require(:visit).permit(:name, :place_id, :started_at, :ended_at, :status)
  end
end
