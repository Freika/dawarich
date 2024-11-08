# frozen_string_literal: true

class Settings::UsersController < ApplicationController
  before_action :authenticate_user!
  before_action :authenticate_admin!

  def index
    @users = User.order(created_at: :desc)
  end

  def edit
    @user = User.find(params[:id])
  end

  def update
    @user = User.find(params[:id])

    if @user.update(user_params)
      redirect_to settings_users_url, notice: 'User was successfully updated.'
    else
      redirect_to settings_users_url, notice: 'User could not be updated.', status: :unprocessable_entity
    end
  end

  def create
    @user = User.new(
      email: user_params[:email],
      password: 'password',
      password_confirmation: 'password'
    )

    if @user.save
      redirect_to settings_users_url,
                  notice: "User was successfully created, email is #{@user.email}, password is \"password\"."
    else
      redirect_to settings_users_url, notice: 'User could not be created.', status: :unprocessable_entity
    end
  end

  def destroy
    @user = User.find(params[:id])

    if @user.destroy
      redirect_to settings_url, notice: 'User was successfully deleted.'
    else
      redirect_to settings_url, notice: 'User could not be deleted.', status: :unprocessable_entity
    end
  end

  private

  def user_params
    params.require(:user).permit(:email)
  end
end
