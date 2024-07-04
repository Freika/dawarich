# frozen_string_literal: true

class NotificationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_notification, only: %i[show destroy]

  def index
    @notifications = current_user.notifications.paginate(page: params[:page], per_page: 25)
  end

  def show; end

  def destroy
    @notification.destroy!
    redirect_to notifications_url, notice: 'Notification was successfully destroyed.', status: :see_other
  end

  private

  def set_notification
    @notification = Notification.find(params[:id])
  end
end
