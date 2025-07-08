# frozen_string_literal: true

class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  def google_oauth2
    handle_auth('Google')
  end

  def github
    handle_auth('Github')
  end

  def microsoft_office365
    handle_auth('Microsoft')
  end

  def openid_connect
    # Determine which OpenID Connect provider was used
    provider_name = request.env['omniauth.auth']['provider']
    case provider_name
    when 'authentik'
      handle_auth('Authentik')
    when 'authelia'
      handle_auth('Authelia')
    when 'keycloak'
      handle_auth('Keycloak')
    else
      handle_auth('OpenID Connect')
    end
  end

  def failure
    redirect_to root_path, alert: 'Authentication failed, please try again.'
  end

  private

  def handle_auth(kind)
    @user = User.from_omniauth(request.env['omniauth.auth'])

    if @user.persisted?
      flash[:notice] = I18n.t 'devise.omniauth_callbacks.success', kind: kind
      sign_in_and_redirect @user, event: :authentication
    else
      session['devise.oauth_data'] = request.env['omniauth.auth'].except(:extra)
      redirect_to new_user_registration_url, alert: @user.errors.full_messages.join("\n")
    end
  end
end