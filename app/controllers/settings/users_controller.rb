# frozen_string_literal: true

class Settings::UsersController < ApplicationController
  before_action :authenticate_user!
  before_action :authenticate_admin!

  def create
    @user = User.new(
      email: user_params[:email],
      password: 'password',
      password_confirmation: 'password'
    )

    if @user.save
      redirect_to settings_url,
                  notice: "User was successfully created, email is #{@user.email}, password is \"password\"."
    else
      redirect_to settings_url, notice: 'User could not be created.', status: :unprocessable_entity
    end
  end

  private

  def user_params
    params.require(:user).permit(:email)
  end
end
