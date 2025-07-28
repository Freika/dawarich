# frozen_string_literal: true

class Settings::UsersController < ApplicationController
  before_action :authenticate_self_hosted!, except: [:export, :import]
  before_action :authenticate_admin!, except: [:export, :import]
  before_action :authenticate_user!

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
    files_params = params.dig(:user_import, :files)
    raw_files = Array(files_params).reject(&:blank?)

    if raw_files.empty?
      redirect_to edit_user_registration_path, alert: 'Please select a ZIP archive to import.'
      return
    end

    created_imports = []

    raw_files.each do |item|
      next if item.is_a?(ActionDispatch::Http::UploadedFile)

      import = create_import_from_signed_id(item)
      created_imports << import if import.present?
    end

    if created_imports.any?
      redirect_to edit_user_registration_path,
                  notice: 'Your data import has been started. You will receive a notification when it completes.'
    else
      redirect_to edit_user_registration_path,
                  alert: 'No valid file references were found. Please upload files using the file selector.'
    end
  rescue StandardError => e
    if created_imports.present?
      import_ids = created_imports.map(&:id).compact
      Import.where(id: import_ids).destroy_all if import_ids.any?
    end

    ExceptionReporter.call(e, 'User data import failed to start')
    redirect_to edit_user_registration_path,
                alert: 'An error occurred while starting the import. Please try again.'
  end

  private

  def user_params
    params.require(:user).permit(:email, :password)
  end

  def create_import_from_signed_id(signed_id)
    Rails.logger.debug "Creating user data import from signed ID: #{signed_id[0..20]}..."

    blob = ActiveStorage::Blob.find_signed(signed_id)

    validate_archive_blob(blob)

    import = current_user.imports.build(
      name: blob.filename.to_s,
      source: :user_data_archive
    )

    import.file.attach(blob)

    import.save!

    import
  end

  def validate_archive_blob(blob)
    unless blob.content_type == 'application/zip' ||
           blob.content_type == 'application/x-zip-compressed' ||
           File.extname(blob.filename.to_s).downcase == '.zip'

      redirect_to edit_user_registration_path, alert: 'Please upload a valid ZIP file.' and return
    end
  end
end
