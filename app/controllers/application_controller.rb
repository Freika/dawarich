# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Pundit::Authorization

  before_action :unread_notifications

  protected

  def unread_notifications
    return [] unless current_user

    @unread_notifications ||= Notification.where(user: current_user).unread
  end

  def authenticate_admin!
    return if current_user&.admin?

    redirect_to root_path, notice: 'You are not authorized to perform this action.', status: :see_other
  end

  def authenticate_self_hosted!
    return if DawarichSettings.self_hosted?

    redirect_to root_path, notice: 'You are not authorized to perform this action.', status: :see_other
  end
end
