# frozen_string_literal: true

class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  def github
    handle_auth('GitHub')
  end

  def google_oauth2
    handle_auth('Google')
  end

  def openid_connect
    handle_auth('OpenID Connect')
  end

  def failure
    error_type = request.env['omniauth.error.type']
    error = request.env['omniauth.error']

    # Provide user-friendly error messages
    error_message =
      case error_type
      when :invalid_credentials
        'Invalid credentials. Please check your username and password.'
      when :timeout
        'Connection timeout. Please try again.'
      when :csrf_detected
        'Security error detected. Please try again.'
      else
        if error&.message&.include?('Discovery')
          'Unable to connect to authentication provider. Please contact your administrator.'
        elsif error&.message&.include?('Issuer mismatch')
          'Authentication provider configuration error. Please contact your administrator.'
        else
          "Authentication failed: #{params[:message] || error&.message || 'Unknown error'}"
        end
      end

    redirect_to root_path, alert: error_message
  end

  private

  def handle_auth(provider)
    @user = User.from_omniauth(request.env['omniauth.auth'])

    if @user&.persisted?
      flash[:notice] = I18n.t 'devise.omniauth_callbacks.success', kind: provider
      sign_in_and_redirect @user, event: :authentication
    elsif @user.nil?
      # User creation was rejected (e.g., OIDC auto-register disabled)
      error_message = if provider == 'OpenID Connect' && !oidc_auto_register_enabled?
                        'Your account must be created by an administrator before you can sign in with OIDC. ' \
                        'Please contact your administrator.'
                      else
                        'Unable to create your account. Please try again or contact support.'
                      end
      redirect_to root_path, alert: error_message
    else
      redirect_to new_user_registration_url, alert: @user.errors.full_messages.join("\n")
    end
  rescue Auth::FindOrCreateOauthUser::LinkVerificationSent
    redirect_to new_user_session_path,
                alert: 'This email already has a Dawarich account. We sent a confirmation link to that address — ' \
                       "click it to link your #{provider} account, then sign in."
  rescue Auth::FindOrCreateOauthUser::UnverifiedEmail
    redirect_to new_user_session_path,
                alert: "Your #{provider} email is not verified. Verify it with the provider, " \
                       'then try again — or sign in with your existing password.'
  end

  def oidc_auto_register_enabled?
    OIDC_AUTO_REGISTER
  end
end
