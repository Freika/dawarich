# frozen_string_literal: true

class NotificationsController < ApplicationController
  self.page_refresh_morphing = true

  before_action :authenticate_user!
  before_action :set_notification, only: %i[show open destroy]

  def index
    @notifications =
      current_user.notifications.order(created_at: :desc).page(params[:page]).per(20)
  end

  def show
    mark_read
  end

  # From the bell: mark it read and go straight to what it is about. An error
  # opens its own page instead: the message and what to do about it are there,
  # next to a button for the destination.
  def open
    mark_read
    destination = @notification.safe_action_path unless @notification.error?
    redirect_to destination || notification_path(@notification)
  end

  def mark_as_read
    current_user.notifications.unread.update_all(read_at: Time.zone.now)
    # From the bell: update this tab in place instead of leaving the page. If
    # the tab is a notification page, the broadcast has to refresh it as well.
    inline = ActiveModel::Type::Boolean.new.cast(params[:inline])
    Notification.broadcast_read_all_for(current_user, include_requester: inline)
    return render(turbo_stream: bell_cleared_streams) if inline

    redirect_to notifications_url, notice: I18n.t('controllers.notifications.all_notifications_marked_as_read'),
status: :see_other
  end

  def destroy_all
    current_user.notifications.delete_all
    Notification.broadcast_delete_all_for(current_user)
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

  # The count is read back rather than assumed zero: a notification can arrive
  # between the update and this render.
  def bell_cleared_streams
    [
      turbo_stream.replace('notifications-badge', partial: 'notifications/badge',
                                                  locals: { count: current_user.notifications.unread.count }),
      turbo_stream.remove_all('.notification-item')
    ]
  end

  def mark_read
    @notification.update!(read_at: Time.zone.now) unless @notification.read_at?
  end

  def set_notification
    @notification = current_user.notifications.find(params[:id])
  end
end
