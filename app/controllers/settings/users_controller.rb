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
      redirect_to settings_users_url, notice: I18n.t('controllers.settings.users.user_was_successfully_updated')
    else
      redirect_to settings_users_url,
                  alert: I18n.t('controllers.settings.users.user_could_not_be_updated_to_sentence',
                                errors: @user.errors.full_messages.to_sentence),
                  status: :see_other
    end
  end

  def create
    @user = User.new(
      email: user_params[:email],
      password: user_params[:password],
      password_confirmation: user_params[:password]
    )

    if @user.save
      redirect_to settings_users_url, notice: I18n.t('controllers.settings.users.user_was_successfully_created')
    else
      redirect_to settings_users_url,
                  alert: I18n.t('controllers.settings.users.user_could_not_be_created_to_sentence',
                                errors: @user.errors.full_messages.to_sentence),
                  status: :see_other
    end
  end

  def destroy
    @user = User.find(params[:id])

    unless @user.can_delete_account?
      redirect_to settings_users_url,
                  alert: I18n.t('controllers.settings.users.cannot_delete_account_while_being_owner_of_a_family_which'),
                  status: :see_other
      return
    end

    Users::DestroyJob.perform_later(@user.id) if @user.mark_as_deleted_atomically!

    redirect_to settings_users_url,
                notice: I18n.t('controllers.settings.users.user_deletion_has_been_initiated_the_account_will_be_fully')
  end

  def regenerate_api_key
    @user = User.find(params[:id])
    @user.update!(api_key: SecureRandom.hex(32))

    redirect_to settings_user_url(@user), notice: I18n.t('controllers.settings.users.api_key_has_been_regenerated')
  end

  def send_password_reset
    @user = User.find(params[:id])
    @user.send_reset_password_instructions

    redirect_to settings_user_url(@user),
                notice: I18n.t('controllers.settings.users.password_reset_email_has_been_sent')
  end

  def update_registration_settings
    enabled = ActiveModel::Type::Boolean.new.cast(params[:registration_enabled])
    DawarichSettings.set_registration_enabled(enabled)

    status = enabled ? 'enabled' : 'disabled'
    redirect_to settings_users_url,
                notice: I18n.t('controllers.settings.users.user_registration_has_been_status', status: status)
  end

  def export
    current_user.export_data

    redirect_to exports_path,
                notice: I18n.t('controllers.settings.users.your_data_is_being_exported_you_will_receive_a_notification')
  end

  def import
    if params[:archive].blank?
      redirect_to edit_user_registration_path,
                  alert: I18n.t('controllers.settings.users.please_select_a_zip_archive_to_import')
      return
    end

    import =
      create_import_from_signed_archive_id(params[:archive])

    if import.save
      redirect_to edit_user_registration_path,
                  notice: I18n.t('controllers.settings.users.your_data_import_has_been_started_you_will_receive_a')
    else
      redirect_to edit_user_registration_path,
                  alert: I18n.t('controllers.settings.users.failed_to_start_import_please_try_again')
    end
  rescue StandardError => e
    ExceptionReporter.call(e, 'User data import failed to start')
    redirect_to edit_user_registration_path,
                alert: I18n.t('controllers.settings.users.an_error_occurred_while_starting_the_import_please_try_again')
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
      I18n.t('controllers.settings.users.cannot_remove_last_admin_role')
    else
      I18n.t('controllers.settings.users.cannot_disable_last_admin')
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

      redirect_to edit_user_registration_path,
                  alert: I18n.t('controllers.settings.users.please_upload_a_valid_zip_file') and return
    end
  end

  def validate_blob_file_type(blob)
    unless ['application/zip', 'application/x-zip-compressed'].include?(blob.content_type) ||
           File.extname(blob.filename.to_s).downcase == '.zip'

      raise StandardError, I18n.t('controllers.settings.users.please_upload_a_valid_zip_file')
    end
  end
end
