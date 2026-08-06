# frozen_string_literal: true

class Settings::GeneralController < ApplicationController
  before_action :authenticate_user!

  def index; end

  def update
    update_locale
    update_timezone
    update_email_settings
    update_supporter_settings

    if current_user.save
      redirect_to settings_general_index_path, notice: I18n.t('controllers.settings.general.settings_updated')
    else
      redirect_to settings_general_index_path, alert: I18n.t('controllers.settings.general.failed_to_update_settings')
    end
  end

  def verify_supporter
    email = params[:supporter_email]&.downcase&.strip
    github_username = params[:supporter_github_username]&.strip

    if email.blank? && github_username.blank?
      return redirect_to settings_general_index_path,
                         alert: I18n.t('controllers.settings.general.please_enter_an_email_address_or_github_username')
    end

    current_user.settings['supporter_email'] = email if email.present?
    current_user.settings['supporter_github_username'] = github_username if github_username.present?
    current_user.save!

    # Clear cached verification so we get a fresh result
    Rails.cache.delete(Supporter::VerifyEmail.new(email).cache_key) if email.present?
    Rails.cache.delete(Supporter::VerifyGithubUsername.new(github_username).cache_key) if github_username.present?

    if current_user.reload.supporter?
      platform = current_user.supporter_platform&.titleize
      notice = I18n.t(
        'controllers.settings.general.verified_thank_you_for_supporting_dawarich_via_platform',
        platform: platform
      )
      redirect_to settings_general_index_path,
                  notice: notice
    else
      redirect_to settings_general_index_path,
                  alert: I18n.t('controllers.settings.general.not_found_in_supporter_list_make_sure_you_re_using')
    end
  end

  private

  # Written here rather than left to the locale around_action: that one saves
  # with `update_all`, which the `current_user.save` below would overwrite with
  # the settings this request loaded.
  def update_locale
    locale = supported_locale(params[:locale])
    return unless locale

    current_user.settings['locale'] = locale.to_s
  end

  def update_timezone
    return unless params.key?(:timezone) && ActiveSupport::TimeZone[params[:timezone]]

    current_user.settings['timezone'] = params[:timezone]
  end

  def update_email_settings
    digest_keys_written = false

    if params.key?(:monthly_digest_emails_enabled)
      current_user.settings['monthly_digest_emails_enabled'] =
        ActiveModel::Type::Boolean.new.cast(params[:monthly_digest_emails_enabled])
      digest_keys_written = true
    end

    if params.key?(:yearly_digest_emails_enabled)
      current_user.settings['yearly_digest_emails_enabled'] =
        ActiveModel::Type::Boolean.new.cast(params[:yearly_digest_emails_enabled])
      digest_keys_written = true
    end

    current_user.settings.delete('digest_emails_enabled') if digest_keys_written

    return unless params.key?(:news_emails_enabled)

    current_user.settings['news_emails_enabled'] =
      ActiveModel::Type::Boolean.new.cast(params[:news_emails_enabled])
  end

  def update_supporter_settings
    current_user.settings['supporter_email'] = params[:supporter_email] if params.key?(:supporter_email)
    if params.key?(:supporter_github_username)
      current_user.settings['supporter_github_username'] = params[:supporter_github_username]
    end
    return unless params.key?(:show_supporter_badge)

    current_user.settings['show_supporter_badge'] =
      ActiveModel::Type::Boolean.new.cast(params[:show_supporter_badge])
  end
end
