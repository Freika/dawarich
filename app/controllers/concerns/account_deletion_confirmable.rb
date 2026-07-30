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
      'Type your email address to confirm deletion.'
    else
      'Provide your current password to delete your account.'
    end
  end

  def log_failed_account_deletion(user)
    Rails.logger.warn("Account deletion confirmation failed for user_id=#{user.id}")
  end
end
