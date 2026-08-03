# frozen_string_literal: true

module AccountDeletionConfirmable
  extend ActiveSupport::Concern

  private

  def account_deletion_confirmed?(user)
    return true if user.valid_password?(params[:password].to_s)

    user.oauth_user? && params[:confirm_email].to_s.strip.casecmp?(user.email)
  end

  def account_deletion_confirmation_error(user)
    if user.oauth_user?
      I18n.t('controllers.concerns.account_deletion_confirmable.confirm_with_email')
    else
      I18n.t('controllers.concerns.account_deletion_confirmable.confirm_with_password')
    end
  end

  def log_failed_account_deletion(user)
    Rails.logger.warn("Account deletion confirmation failed for user_id=#{user.id}")
  end
end
