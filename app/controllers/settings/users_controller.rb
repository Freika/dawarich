# frozen_string_literal: true

class Settings::UsersController < ApplicationController
  before_action :authenticate_self_hosted!, only: [:export, :import]
  before_action :authenticate_admin!, except: [:export, :import]
  before_action :authenticate_user!, only: [:export, :import]

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
      password: user_params[:password],
      password_confirmation: user_params[:password]
    )

    if @user.save
      redirect_to settings_users_url, notice: 'User was successfully created'
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

  def export
    current_user.export_data

    redirect_to exports_path, notice: 'Your data is being exported. You will receive a notification when it is ready.'
  end

  def import
    unless params[:archive].present?
      redirect_to edit_user_registration_path, alert: 'Please select a ZIP archive to import.'
      return
    end

    archive_file = params[:archive]

    validate_archive_file(archive_file)

    import = current_user.imports.build(
      name: archive_file.original_filename,
      source: :user_data_archive
    )

    import.file.attach(archive_file)

    if import.save
      redirect_to edit_user_registration_path,
                  notice: 'Your data import has been started. You will receive a notification when it completes.'
    else
      redirect_to edit_user_registration_path,
                  alert: 'Failed to start import. Please try again.'
    end
  rescue StandardError => e
    ExceptionReporter.call(e, 'User data import failed to start')
    redirect_to edit_user_registration_path,
                alert: 'An error occurred while starting the import. Please try again.'
  end

  private

  def user_params
    params.require(:user).permit(:email, :password)
  end

  def validate_archive_file(archive_file)
    unless archive_file.content_type == 'application/zip' ||
           archive_file.content_type == 'application/x-zip-compressed' ||
           File.extname(archive_file.original_filename).downcase == '.zip'

      redirect_to edit_user_registration_path, alert: 'Please upload a valid ZIP file.' and return
    end
  end
end
