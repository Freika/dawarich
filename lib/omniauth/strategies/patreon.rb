# frozen_string_literal: true

require 'omniauth-oauth2'

module OmniAuth
  module Strategies
    # OmniAuth strategy for Patreon OAuth2
    class Patreon < OmniAuth::Strategies::OAuth2
      option :name, 'patreon'

      option :client_options,
             site: 'https://www.patreon.com',
             authorize_url: 'https://www.patreon.com/oauth2/authorize',
             token_url: 'https://www.patreon.com/api/oauth2/token'

      option :authorize_params,
             scope: 'identity identity[email]'

      uid { raw_info['data']['id'] }

      info do
        {
          email: raw_info.dig('data', 'attributes', 'email'),
          name: raw_info.dig('data', 'attributes', 'full_name'),
          first_name: raw_info.dig('data', 'attributes', 'first_name'),
          last_name: raw_info.dig('data', 'attributes', 'last_name'),
          image: raw_info.dig('data', 'attributes', 'image_url')
        }
      end

      extra do
        {
          raw_info: raw_info
        }
      end

      def raw_info
        @raw_info ||= access_token.get('/api/oauth2/v2/identity?include=memberships&fields[user]=email,first_name,full_name,last_name,image_url').parsed
      end

      def callback_url
        full_host + callback_path
      end
    end
  end
end
