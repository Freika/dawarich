# frozen_string_literal: true

module Patreon
  # Service to check Patreon patron status
  class PatronChecker
    attr_reader :user

    def initialize(user)
      @user = user
    end

    # Check if user is a patron of a specific creator
    # @param creator_id [String] The Patreon creator ID
    # @return [Boolean] true if user is an active patron
    def patron_of?(creator_id)
      memberships.any? do |membership|
        membership.dig('relationships', 'campaign', 'data', 'id') == creator_id.to_s &&
          membership.dig('attributes', 'patron_status') == 'active_patron'
      end
    end

    # Get all active memberships
    # @return [Array<Hash>] Array of membership data with campaign info
    def memberships
      @memberships ||= fetch_memberships
    end

    # Get detailed membership info for a specific creator
    # @param creator_id [String] The Patreon creator ID
    # @return [Hash, nil] Membership details or nil if not a patron
    def membership_for(creator_id)
      memberships.find do |membership|
        membership.dig('relationships', 'campaign', 'data', 'id') == creator_id.to_s
      end
    end

    private

    def fetch_memberships
      return [] unless valid_token?

      response = make_api_request
      return [] unless response

      extract_memberships(response)
    rescue StandardError => e
      Rails.logger.error("Failed to fetch Patreon memberships: #{e.message}")
      []
    end

    def valid_token?
      return false if user.patreon_access_token.blank?

      # Check if token is expired
      if user.patreon_token_expires_at && user.patreon_token_expires_at < Time.current
        refresh_token!
      end

      user.patreon_access_token.present?
    end

    def refresh_token!
      return false if user.patreon_refresh_token.blank?

      conn = Faraday.new(url: 'https://www.patreon.com') do |f|
        f.request :url_encoded
        f.response :json
        f.adapter Faraday.default_adapter
      end

      response = conn.post('/api/oauth2/token') do |req|
        req.body = {
          grant_type: 'refresh_token',
          refresh_token: user.patreon_refresh_token,
          client_id: ENV['PATREON_CLIENT_ID'],
          client_secret: ENV['PATREON_CLIENT_SECRET']
        }
      end

      if response.success?
        data = response.body
        user.update(
          patreon_access_token: data['access_token'],
          patreon_refresh_token: data['refresh_token'],
          patreon_token_expires_at: Time.current + data['expires_in'].seconds
        )
        true
      else
        Rails.logger.error("Failed to refresh Patreon token: #{response.body}")
        false
      end
    rescue StandardError => e
      Rails.logger.error("Error refreshing Patreon token: #{e.message}")
      false
    end

    def make_api_request
      conn = Faraday.new(url: 'https://www.patreon.com') do |f|
        f.request :url_encoded
        f.response :json
        f.adapter Faraday.default_adapter
      end

      response = conn.get('/api/oauth2/v2/identity') do |req|
        req.headers['Authorization'] = "Bearer #{user.patreon_access_token}"
        req.params = {
          include: 'memberships,memberships.campaign',
          'fields[member]' => 'patron_status,pledge_relationship_start',
          'fields[campaign]' => 'vanity,url'
        }
      end

      response.success? ? response.body : nil
    end

    def extract_memberships(response)
      return [] unless response['included']

      memberships = response['included'].select { |item| item['type'] == 'member' }
      campaigns = response['included'].select { |item| item['type'] == 'campaign' }

      # Enrich memberships with campaign data
      memberships.map do |membership|
        campaign_id = membership.dig('relationships', 'campaign', 'data', 'id')
        campaign = campaigns.find { |c| c['id'] == campaign_id }

        membership.merge('campaign' => campaign) if campaign
      end.compact
    end
  end
end
