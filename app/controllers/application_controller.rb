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
    return if current_user.admin?

    redirect_to root_path, notice: 'You are not authorized to perform this action.', status: :unauthorized
  end

  def authenticate_api_key
    return head :unauthorized unless current_api_user

    true
  end

  def current_api_user
    @current_api_user ||= User.find_by(api_key: params[:api_key])
  end
end
