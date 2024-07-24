# frozen_string_literal: true

class VisitsController < ApplicationController
  before_action
  before_action :set_visit, only: %i[edit update destroy]

  def index
    visits = current_user
             .visits
             .where(status: :pending)
             .or(current_user.visits.where(status: :confirmed))
             .order(started_at: :asc)
             .group_by { |visit| visit.started_at.to_date }
             .map { |k, v| { date: k, visits: v } }

    @visits = Kaminari.paginate_array(visits).page(params[:page]).per(10)
  end

  def edit; end

  def update
    if @visit.update(visit_params)
      redirect_to visits_url, notice: 'Visit was successfully updated.', status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @visit.destroy!
    redirect_to visits_url, notice: 'Visit was successfully destroyed.', status: :see_other
  end

  private

  def set_visit
    @visit = current_user.visits.find(params[:id])
  end

  def visit_params
    params.require(:visit).permit(:name, :started_at, :ended_at, :status)
  end
end
