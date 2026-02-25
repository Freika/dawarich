# frozen_string_literal: true

OmniAuth.config.test_mode = true

module OmniauthHelpers
  def mock_github_auth(email: 'test@github.com')
    OmniAuth.config.mock_auth[:github] = OmniAuth::AuthHash.new({
                                                                  provider: 'github',
      uid: '123545',
      info: {
        email: email,
        name: 'Test User',
        image: 'https://avatars.githubusercontent.com/u/123545'
      },
      credentials: {
        token: 'mock_token',
        expires_at: Time.zone.now + 1.week
      },
      extra: {
        raw_info: {
          login: 'testuser',
          avatar_url: 'https://avatars.githubusercontent.com/u/123545',
          name: 'Test User',
          email: email
        }
      }
                                                                })
  end

  def mock_google_auth(email: 'test@gmail.com')
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new({
                                                                         provider: 'google_oauth2',
      uid: '123545',
      info: {
        email: email,
        name: 'Test User',
        image: 'https://lh3.googleusercontent.com/a/test'
      },
      credentials: {
        token: 'mock_token',
        refresh_token: 'mock_refresh_token',
        expires_at: Time.zone.now + 1.hour
      },
      extra: {
        raw_info: {
          email: email,
          email_verified: true,
          name: 'Test User',
          given_name: 'Test',
          family_name: 'User',
          picture: 'https://lh3.googleusercontent.com/a/test'
        }
      }
                                                                       })
  end

  def mock_openid_connect_auth(email: 'test@oidc.com', _provider_name: 'Authelia')
    OmniAuth.config.mock_auth[:openid_connect] = OmniAuth::AuthHash.new({
                                                                          provider: 'openid_connect',
      uid: '123545',
      info: {
        email: email,
        name: 'Test User',
        image: 'https://example.com/avatar.jpg'
      },
      credentials: {
        token: 'mock_token',
        refresh_token: 'mock_refresh_token',
        expires_at: Time.zone.now + 1.hour,
        id_token: 'mock_id_token'
      },
      extra: {
        raw_info: {
          sub: '123545',
          email: email,
          email_verified: true,
          name: 'Test User',
          preferred_username: 'testuser',
          given_name: 'Test',
          family_name: 'User',
          picture: 'https://example.com/avatar.jpg'
        }
      }
                                                                        })
  end

  def mock_oauth_failure(provider)
    OmniAuth.config.mock_auth[provider] = :invalid_credentials
  end
end

RSpec.configure do |config|
  config.include OmniauthHelpers, type: :request
  config.include OmniauthHelpers, type: :system

  config.before do
    OmniAuth.config.test_mode = true
  end

  config.after do
    OmniAuth.config.mock_auth[:github] = nil
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    OmniAuth.config.mock_auth[:openid_connect] = nil
  end
end
