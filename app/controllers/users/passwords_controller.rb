# frozen_string_literal: true

class Users::PasswordsController < Devise::PasswordsController
  # Mirrors Devise::PasswordsController#update, but a 2FA-enabled account is not
  # auto-signed-in after a reset: it is sent through the OTP challenge, so a
  # password reset cannot bypass the second factor.
  def update
    self.resource = resource_class.reset_password_by_token(resource_params)
    yield resource if block_given?

    if resource.errors.empty?
      resource.unlock_access! if unlockable?(resource)

      if DawarichSettings.two_factor_available? && resource.otp_required_for_login?
        session[:otp_user_id] = resource.id
        session[:otp_challenge_at] = Time.current.to_i
        set_flash_message!(:notice, :updated_not_active)
        return redirect_to new_user_session_path
      end

      if resource_class.sign_in_after_reset_password
        flash_message = resource.active_for_authentication? ? :updated : :updated_not_active
        set_flash_message!(:notice, flash_message)
        resource.after_database_authentication
        sign_in(resource_name, resource)
      else
        set_flash_message!(:notice, :updated_not_active)
      end

      respond_with resource, location: after_resetting_password_path_for(resource)
    else
      set_minimum_password_length
      respond_with resource
    end
  end
end
