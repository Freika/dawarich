# frozen_string_literal: true

class NotificationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_notification, only: %i[show destroy]

  def index
    @notifications =
      current_user.notifications.order(created_at: :desc).paginate(page: params[:page], per_page: 20)
  end

  def show
    @notification.update!(read_at: Time.zone.now) unless @notification.read_at?
  end

  def mark_as_read
    current_user.notifications.unread.update_all(read_at: Time.zone.now)

    redirect_to notifications_url, notice: 'All notifications marked as read.', status: :see_other
  end

  def destroy
    @notification.destroy!
    redirect_to notifications_url, notice: 'Notification was successfully destroyed.', status: :see_other
  end

  private

  def set_notification
    @notification = Notification.find(params[:id])
  end
end
