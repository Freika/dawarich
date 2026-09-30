# frozen_string_literal: true

require 'digest'

# The only path from Cloud account data to the new product analytics project.
# Unknown events and properties fail closed; callers must use controlled values.
class ProductAnalytics
  AD_ATTRIBUTION_EVENTS = %w[user_signed_up trial_started paid_conversion payment_charged payment_refunded].freeze
  AD_ATTRIBUTION_PROPERTIES = %w[ad_source ad_campaign_id].freeze

  EVENTS = {
    'web_first_observed' => [],
    'mobile_first_observed' => %w[installation_cohort app_version],
    'cloud_signup_started' => %w[auth_method app_version],
    'cloud_signup_failed' => %w[auth_method failure_category app_version],
    'user_signed_up' => %w[auth_method],
    'cloud_login_succeeded' => %w[auth_method app_version],
    'cloud_login_failed' => %w[auth_method failure_category app_version],
    'cloud_paywall_requested' => %w[offering app_version],
    'cloud_paywall_presented' => %w[offering app_version],
    'cloud_purchase_attempted' => %w[offering plan app_version],
    'cloud_paywall_closed' => %w[offering result app_version],
    'location_permission_result' => %w[permission result app_version],
    'background_tracking_enabled' => %w[app_version],
    'import_completed' => %w[source count_bucket],
    'first_point_received' => %w[source],
    'user_activated' => %w[activation_method],
    'first_mobile_upload_confirmed' => %w[upload_path count_bucket app_version],
    'trial_started' => %w[provider plan already_activated_at_trial],
    'paid_conversion' => %w[provider plan amount_minor currency amount_eur_minor],
    'payment_charged' => %w[provider plan amount_minor currency amount_eur_minor],
    'trial_expired' => %w[provider plan],
    'subscription_cancellation_scheduled' => %w[provider plan],
    'payment_refunded' => %w[provider amount_minor currency amount_eur_minor]
  }.freeze

  ENUMS = {
    'channel' => %w[mobile web server billing],
    'platform' => %w[ios android web none],
    'auth_method' => %w[email apple google],
    'installation_cohort' => %w[new existing],
    'failure_category' => %w[validation authentication network provider unknown],
    'result' => %w[purchased restored cancelled error entitlement_active granted denied limited],
    'permission' => %w[foreground background],
    'plan' => %w[lite pro family],
    'provider' => %w[paddle apple_iap google_play],
    'activation_method' => %w[import points],
    'upload_path' => %w[js android_native ios_native],
    'count_bucket' => %w[1 2-9 10-99 100-999 1000+],
    'source' => %w[api owntracks overland traccar teslamate other google_semantic_history google_records
                   google_phone_takeout gpx immich_api geojson photoprism_api user_data_archive kml csv tcx fit
                   polarsteps google_photos mobile_photo_library]
  }.freeze

  def self.configured?
    ENV['PRODUCT_POSTHOG_API_KEY'].present? &&
      ENV['PRODUCT_POSTHOG_PERSONAL_API_KEY'].present? &&
      ENV['PRODUCT_POSTHOG_PROJECT_ID'].present?
  end

  def self.capture(user:, event:, channel:, platform: 'none', properties: {}, event_id: SecureRandom.uuid)
    return false if DawarichSettings.self_hosted? || !configured?
    return false unless user.product_analytics_consent? && user.product_analytics_id.present?

    allowed = EVENTS.fetch(event)
    safe = properties.stringify_keys.slice(*allowed)
    safe.each do |key, value|
      raise ArgumentError, "Invalid analytics property: #{key}" unless valid_property?(key, value)
    end
    safe.merge!(ad_attribution(user)) if AD_ATTRIBUTION_EVENTS.include?(event)
    raise ArgumentError, 'Invalid channel' unless ENUMS.fetch('channel').include?(channel)
    raise ArgumentError, 'Invalid platform' unless ENUMS.fetch('platform').include?(platform)

    public_event_id = deterministic_uuid(event_id)
    payload = safe.merge('schema_version' => 1, 'channel' => channel, 'platform' => platform,
                         'event_id' => public_event_id, '$geoip_disable' => true)
    !!PostHog.capture(distinct_id: user.product_analytics_id, event: event, properties: payload,
                      uuid: public_event_id)
  end

  def self.valid_property?(key, value)
    return ENUMS.fetch(key).include?(value.to_s) if ENUMS.key?(key)
    return [true, false].include?(value) if key == 'already_activated_at_trial'
    return value.is_a?(Integer) && value >= 0 if %w[amount_minor amount_eur_minor].include?(key)
    return value.is_a?(String) && value.match?(/\A[A-Z]{3}\z/) if key == 'currency'
    return value == 'google_ads' if key == 'ad_source'
    return value.is_a?(String) && value.match?(/\A[0-9]{1,20}\z/) if key == 'ad_campaign_id'
    return value.is_a?(String) && value.match?(/\A[a-zA-Z0-9._-]{1,64}\z/) if %w[app_version offering].include?(key)

    false
  end

  # posthog-rails adds request URL, IP and user agent to SDK context. This
  # final boundary strips those SDK-added fields immediately before enqueue.
  def self.sanitize_sdk_event(action)
    event = action[:event].to_s
    return nil unless EVENTS.key?(event)
    return nil unless action[:distinct_id].to_s.match?(/\A[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\z/i)

    allowed = EVENTS.fetch(event) + %w[schema_version channel platform event_id $geoip_disable]
    allowed += AD_ATTRIBUTION_PROPERTIES if AD_ATTRIBUTION_EVENTS.include?(event)
    action[:properties] = action.fetch(:properties, {}).stringify_keys.slice(*allowed)
    return nil unless action[:properties].slice('schema_version', 'channel', 'platform', 'event_id',
                                                '$geoip_disable').size == 5
    return nil unless action[:properties].all? do |key, value|
      case key
      when 'schema_version' then value == 1
      when 'channel', 'platform' then ENUMS.fetch(key).include?(value)
      when 'event_id' then value.is_a?(String) && value.match?(/\A[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\z/i)
      when '$geoip_disable' then value == true
      else valid_property?(key, value)
      end
    end

    action
  end

  def self.deterministic_uuid(event_id)
    hex = Digest::SHA256.hexdigest(event_id.to_s)[0, 32].chars
    hex[12] = '5'
    hex[16] = ((hex[16].to_i(16) & 0x3) | 0x8).to_s(16)
    [hex[0, 8].join, hex[8, 4].join, hex[12, 4].join, hex[16, 4].join, hex[20, 12].join].join('-')
  end

  def self.ad_attribution(user)
    return {} unless user.utm_source == 'google' && user.utm_medium == 'cpc'

    campaign_id = user.utm_campaign.to_s
    attribution = { 'ad_source' => 'google_ads' }
    attribution['ad_campaign_id'] = campaign_id if valid_property?('ad_campaign_id', campaign_id)
    attribution
  end

  private_class_method :valid_property?, :deterministic_uuid, :ad_attribution
end
