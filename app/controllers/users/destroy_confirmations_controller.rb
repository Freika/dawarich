# frozen_string_literal: true

class Users::DestroyConfirmationsController < ApplicationController
  before_action :no_store_headers

  def show
    result =
      begin
        Users::VerifyDestroyToken.new(params[:token]).call
      rescue Users::VerifyDestroyToken::TokenReplayed
        alert = I18n.t('controllers.users.destroy_confirmations.this_deletion_link_has_already_been_used')
        return redirect_to(new_user_session_path,
                           alert: alert)
      rescue Users::VerifyDestroyToken::InvalidToken
        return redirect_to(new_user_session_path,
                           alert: I18n.t('controllers.users.destroy_confirmations.deletion_link_invalid_or_expired'))
      end

    user = result.user

    unless user.can_delete_account?
      alert = I18n.t('controllers.users.destroy_confirmations.cannot_delete_account_while_you_own_a_family_with_other')
      return redirect_to(
        new_user_session_path,
        alert: alert
      )
    end

    unless Users::VerifyDestroyToken.consume!(result.jti)
      alert = I18n.t('controllers.users.destroy_confirmations.this_deletion_link_has_already_been_used')
      return redirect_to(new_user_session_path,
                         alert: alert)
    end

    Users::DestroyJob.perform_later(user.id) if user.mark_as_deleted_atomically!

    sign_out(user) if user_signed_in? && current_user&.id == user.id

    notice = I18n.t('controllers.users.destroy_confirmations.your_account_has_been_scheduled_for_deletion_we_are_sorry')
    redirect_to new_user_session_path, notice: notice
  end

  private

  def no_store_headers
    response.headers['Cache-Control'] = 'no-store'
    response.headers['Pragma'] = 'no-cache'
  end
end
