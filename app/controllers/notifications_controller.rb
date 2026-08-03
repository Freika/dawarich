# frozen_string_literal: true

class NotificationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_notification, only: %i[show destroy]

  def index
    @notifications =
      current_user.notifications.order(created_at: :desc).page(params[:page]).per(20)
  end

  def show
    @notification.update!(read_at: Time.zone.now) unless @notification.read_at?
  end

  def mark_as_read
    current_user.notifications.unread.update_all(read_at: Time.zone.now)
    redirect_to notifications_url, notice: I18n.t('controllers.notifications.all_notifications_marked_as_read'),
status: :see_other
  end

  def destroy_all
    current_user.notifications.destroy_all
    notice = I18n.t('controllers.notifications.all_notifications_where_successfully_destroyed')
    redirect_to notifications_url,
                notice: notice, status: :see_other
  end

  def destroy
    @notification.destroy!
    notice = I18n.t('controllers.notifications.notification_was_successfully_destroyed')
    redirect_to notifications_url, notice: notice,
status: :see_other
  end

  private

  def set_notification
    @notification = current_user.notifications.find(params[:id])
  end
end
