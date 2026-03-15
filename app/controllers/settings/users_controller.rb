# frozen_string_literal: true

class Settings::UsersController < ApplicationController
  before_action :authenticate_self_hosted!, except: %i[export import]
  before_action :authenticate_user!
  before_action :authenticate_admin!, except: %i[export import]

  def index
    @users = filtered_users.order(created_at: :desc).page(params[:page]).per(25)
  end

  def show
    @user = User.find(params[:id])
  end

  def edit
    @user = User.find(params[:id])
  end

  def update
    @user = User.find(params[:id])

    return redirect_to settings_users_url, alert: last_admin_alert_message if last_admin_protection_needed?

    update_params = filtered_user_params

    if @user.update(update_params)
      redirect_to settings_users_url, notice: 'User was successfully updated.'
    else
      redirect_to settings_users_url, notice: 'User could not be updated.', status: :unprocessable_content
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
      redirect_to settings_users_url, notice: 'User could not be created.', status: :unprocessable_content
    end
  end

  def destroy
    @user = User.find(params[:id])

    unless @user.can_delete_account?
      redirect_to settings_users_url,
                  alert: 'Cannot delete account while being owner of a family which has other members.',
                  status: :unprocessable_content
      return
    end

    Users::DestroyJob.perform_later(@user.id) if @user.mark_as_deleted_atomically!

    redirect_to settings_users_url,
                notice: 'User deletion has been initiated. The account will be fully removed shortly.'
  end

  def regenerate_api_key
    @user = User.find(params[:id])
    @user.update!(api_key: SecureRandom.hex(16))

    redirect_to settings_user_url(@user), notice: 'API key has been regenerated.'
  end

  def send_password_reset
    @user = User.find(params[:id])
    @user.send_reset_password_instructions

    redirect_to settings_user_url(@user), notice: 'Password reset email has been sent.'
  end

  def update_registration_settings
    enabled = ActiveModel::Type::Boolean.new.cast(params[:registration_enabled])
    DawarichSettings.set_registration_enabled(enabled)

    status = enabled ? 'enabled' : 'disabled'
    redirect_to settings_users_url, notice: "User registration has been #{status}."
  end

  def export
    current_user.export_data

    redirect_to exports_path, notice: 'Your data is being exported. You will receive a notification when it is ready.'
  end

  def import
    if params[:archive].blank?
      redirect_to edit_user_registration_path, alert: 'Please select a ZIP archive to import.'
      return
    end

    import =
      create_import_from_signed_archive_id(params[:archive])

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

  def filtered_users
    return User.all if params[:search].blank?

    User.where('email ILIKE ?', "%#{User.sanitize_sql_like(params[:search])}%")
  end

  def user_params
    params.require(:user).permit(:email, :password, :admin, :status)
  end

  def filtered_user_params
    up = user_params.to_h
    up.delete('password') if up['password'].blank?
    up
  end

  def last_admin_protection_needed?
    return false unless @user.admin? && sole_admin?

    removing_admin_role? || disabling_user?
  end

  def removing_admin_role?
    user_params.key?(:admin) && user_params[:admin].to_s == '0'
  end

  def disabling_user?
    user_params.key?(:status) && user_params[:status] != 'active'
  end

  def sole_admin?
    User.where(admin: true).count == 1
  end

  def last_admin_alert_message
    if removing_admin_role?
      'Cannot remove admin role from the last admin user.'
    else
      'Cannot disable the last admin user.'
    end
  end

  def create_import_from_signed_archive_id(signed_id)
    Rails.logger.debug "Creating archive import from signed ID: #{signed_id[0..20]}..."

    blob = ActiveStorage::Blob.find_signed(signed_id)

    # Validate that it's a ZIP file
    validate_blob_file_type(blob)

    import_name = generate_unique_import_name(blob.filename.to_s)
    import = current_user.imports.build(
      name: import_name,
      source: :user_data_archive
    )
    import.file.attach(blob)

    import
  end

  def generate_unique_import_name(original_name)
    return original_name unless current_user.imports.exists?(name: original_name)

    # Extract filename and extension
    basename = File.basename(original_name, File.extname(original_name))
    extension = File.extname(original_name)

    # Add current datetime
    timestamp = Time.current.strftime('%Y%m%d_%H%M%S')
    "#{basename}_#{timestamp}#{extension}"
  end

  def validate_archive_file(archive_file)
    unless ['application/zip', 'application/x-zip-compressed'].include?(archive_file.content_type) ||
           File.extname(archive_file.original_filename).downcase == '.zip'

      redirect_to edit_user_registration_path, alert: 'Please upload a valid ZIP file.' and return
    end
  end

  def validate_blob_file_type(blob)
    unless ['application/zip', 'application/x-zip-compressed'].include?(blob.content_type) ||
           File.extname(blob.filename.to_s).downcase == '.zip'

      raise StandardError, 'Please upload a valid ZIP file.'
    end
  end
end
