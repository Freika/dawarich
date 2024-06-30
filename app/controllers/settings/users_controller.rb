# frozen_string_literal: true

class Settings::UsersController < ApplicationController
  before_action :authenticate_user!
  before_action :authenticate_first_user!

  def create
    @user = User.new(
      email: user_params[:email],
      password: 'password',
      password_confirmation: 'password'
    )

    if @user.save
      redirect_to settings_url, notice: "User was successfully created, email is #{@user.email}, password is \"password\"."
    else
      redirect_to settings_url, notice: 'User could not be created.', status: :unprocessable_entity
    end
  end

  private

  def user_params
    params.require(:user).permit(:email)
  end

  def authenticate_first_user!
    return if current_user == User.first

    redirect_to settings_users_url, notice: 'You are not authorized to perform this action.', status: :unauthorized
  end
end
