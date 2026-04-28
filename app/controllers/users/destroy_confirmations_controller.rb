# frozen_string_literal: true

class Users::DestroyConfirmationsController < ApplicationController
  before_action :no_store_headers

  def show
    result =
      begin
        Users::VerifyDestroyToken.new(params[:token]).call
      rescue Users::VerifyDestroyToken::TokenReplayed
        return redirect_to(new_user_session_path, alert: 'This deletion link has already been used.')
      rescue Users::VerifyDestroyToken::InvalidToken
        return redirect_to(new_user_session_path, alert: 'Deletion link invalid or expired.')
      end

    user = result.user

    unless user.can_delete_account?
      return redirect_to(
        new_user_session_path,
        alert: 'Cannot delete account while you own a family with other members. ' \
               'Transfer ownership or remove members first.'
      )
    end

    unless Users::VerifyDestroyToken.consume!(result.jti)
      return redirect_to(new_user_session_path, alert: 'This deletion link has already been used.')
    end

    Users::DestroyJob.perform_later(user.id) if user.mark_as_deleted_atomically!

    sign_out(user) if user_signed_in? && current_user&.id == user.id

    redirect_to new_user_session_path,
                notice: 'Your account has been scheduled for deletion. We are sorry to see you go.'
  end

  private

  def no_store_headers
    response.headers['Cache-Control'] = 'no-store'
    response.headers['Pragma'] = 'no-cache'
  end
end
