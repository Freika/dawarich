# frozen_string_literal: true

class Settings::OauthController < ApplicationController
  before_action :authenticate_user!
  before_action :authenticate_admin!

  def index
    @oauth_config = {
      google: {
        configured: google_configured?,
        client_id: ENV['GOOGLE_CLIENT_ID'].present?,
        client_secret: ENV['GOOGLE_CLIENT_SECRET'].present?
      },
      github: {
        configured: github_configured?,
        client_id: ENV['GITHUB_CLIENT_ID'].present?,
        client_secret: ENV['GITHUB_CLIENT_SECRET'].present?
      },
      microsoft: {
        configured: microsoft_configured?,
        client_id: ENV['MICROSOFT_CLIENT_ID'].present?,
        client_secret: ENV['MICROSOFT_CLIENT_SECRET'].present?
      },
      authentik: {
        configured: authentik_configured?,
        host: ENV['AUTHENTIK_HOST'].present?,
        issuer: ENV['AUTHENTIK_ISSUER'].present?,
        client_id: ENV['AUTHENTIK_CLIENT_ID'].present?,
        client_secret: ENV['AUTHENTIK_CLIENT_SECRET'].present?
      },
      authelia: {
        configured: authelia_configured?,
        host: ENV['AUTHELIA_HOST'].present?,
        issuer: ENV['AUTHELIA_ISSUER'].present?,
        client_id: ENV['AUTHELIA_CLIENT_ID'].present?,
        client_secret: ENV['AUTHELIA_CLIENT_SECRET'].present?
      },
      keycloak: {
        configured: keycloak_configured?,
        host: ENV['KEYCLOAK_HOST'].present?,
        issuer: ENV['KEYCLOAK_ISSUER'].present?,
        client_id: ENV['KEYCLOAK_CLIENT_ID'].present?,
        client_secret: ENV['KEYCLOAK_CLIENT_SECRET'].present?
      }
    }
  end

  private

  def google_configured?
    ENV['GOOGLE_CLIENT_ID'].present? && ENV['GOOGLE_CLIENT_SECRET'].present?
  end

  def github_configured?
    ENV['GITHUB_CLIENT_ID'].present? && ENV['GITHUB_CLIENT_SECRET'].present?
  end

  def microsoft_configured?
    ENV['MICROSOFT_CLIENT_ID'].present? && ENV['MICROSOFT_CLIENT_SECRET'].present?
  end

  def authentik_configured?
    ENV['AUTHENTIK_HOST'].present? && 
    ENV['AUTHENTIK_ISSUER'].present? && 
    ENV['AUTHENTIK_CLIENT_ID'].present? && 
    ENV['AUTHENTIK_CLIENT_SECRET'].present?
  end

  def authelia_configured?
    ENV['AUTHELIA_HOST'].present? && 
    ENV['AUTHELIA_ISSUER'].present? && 
    ENV['AUTHELIA_CLIENT_ID'].present? && 
    ENV['AUTHELIA_CLIENT_SECRET'].present?
  end

  def keycloak_configured?
    ENV['KEYCLOAK_HOST'].present? && 
    ENV['KEYCLOAK_ISSUER'].present? && 
    ENV['KEYCLOAK_CLIENT_ID'].present? && 
    ENV['KEYCLOAK_CLIENT_SECRET'].present?
  end
end