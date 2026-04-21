# frozen_string_literal: true

class Trial::WelcomeController < ApplicationController
  def show
    decoded = Subscription::DecodeJwtToken.new(params[:token]).call
    user = User.find(decoded[:user_id])
    sign_in(user) unless current_user == user
    @user = user
  rescue JWT::DecodeError, ActiveRecord::RecordNotFound
    redirect_to new_user_session_path, alert: 'Link expired. Please sign in.'
  end
end
