# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProductAnalytics do
  let(:user) { create(:user, product_analytics_consent: true, product_analytics_id: SecureRandom.uuid) }

  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('PRODUCT_POSTHOG_API_KEY').and_return('phc_test')
    allow(ENV).to receive(:[]).with('PRODUCT_POSTHOG_PERSONAL_API_KEY').and_return('personal_test')
    allow(ENV).to receive(:[]).with('PRODUCT_POSTHOG_PROJECT_ID').and_return('123')
    allow(PostHog).to receive(:capture).and_return(true)
  end

  it 'captures a vetted event with a pseudonymous identity' do
    expect(described_class.capture(user: user, event: 'cloud_paywall_closed', channel: 'mobile', platform: 'ios',
                                   properties: { result: 'cancelled', email: 'private@example.com' })).to be(true)
    expect(PostHog).to have_received(:capture).with(hash_including(distinct_id: user.product_analytics_id,
                                                                   event: 'cloud_paywall_closed',
                                                                   properties: hash_excluding('email')))
  end

  it 'does not capture for an undecided account' do
    user.update!(product_analytics_consent: nil)
    expect(described_class.capture(user: user, event: 'cloud_paywall_closed', channel: 'mobile')).to be(false)
    expect(PostHog).not_to have_received(:capture)
  end

  it 'does not capture unless erasure is configured' do
    allow(ENV).to receive(:[]).with('PRODUCT_POSTHOG_PERSONAL_API_KEY').and_return(nil)
    expect(described_class.capture(user: user, event: 'cloud_paywall_closed', channel: 'mobile')).to be(false)
    expect(PostHog).not_to have_received(:capture)
  end

  it 'attributes a first paid conversion to a saved Google Ads campaign' do
    user.update!(utm_source: 'google', utm_medium: 'cpc', utm_campaign: '12345678901234567890')

    expect(described_class.capture(user: user, event: 'paid_conversion', channel: 'billing',
                                   properties: { provider: 'paddle', amount_minor: 1799,
                                                 currency: 'EUR' })).to be(true)
    attribution = hash_including('ad_source' => 'google_ads', 'ad_campaign_id' => '12345678901234567890')
    expect(PostHog).to have_received(:capture).with(hash_including(event: 'paid_conversion',
                                                                   properties: attribution))
  end

  it 'keeps Google Ads fields off arbitrary campaign text and non-ad UTM values' do
    captured = []
    allow(PostHog).to receive(:capture) do |event|
      captured << event
      true
    end

    user.update!(utm_source: 'google', utm_medium: 'cpc', utm_campaign: 'private@example.com')
    described_class.capture(user: user, event: 'user_signed_up', channel: 'server',
                            properties: { auth_method: 'email' })
    expect(captured.last[:properties]).to include('ad_source' => 'google_ads')
    expect(captured.last[:properties]).not_to have_key('ad_campaign_id')

    user.update!(utm_source: 'newsletter', utm_medium: 'email', utm_campaign: '123')
    described_class.capture(user: user, event: 'paid_conversion', channel: 'billing')
    expect(captured.last[:event]).to eq('paid_conversion')
    expect(captured.last[:properties]).not_to include('ad_source', 'ad_campaign_id')
  end

  it 'refuses free-form values that could contain personal data' do
    expect do
      described_class.capture(user: user, event: 'cloud_paywall_closed', channel: 'mobile',
                              properties: { result: 'user@example.com' })
    end.to raise_error(ArgumentError)
  end

  it 'strips Rails SDK request context before sending to PostHog' do
    event = { event: 'cloud_paywall_closed', distinct_id: user.product_analytics_id,
              properties: { 'result' => 'cancelled', 'schema_version' => 1, 'channel' => 'mobile',
                            'platform' => 'ios', 'event_id' => SecureRandom.uuid, '$geoip_disable' => true,
                            '$current_url' => 'https://example.com/private',
                            '$ip' => '192.0.2.1', '$user_agent' => 'private' } }
    expect(described_class.sanitize_sdk_event(event)[:properties].keys).not_to include('$current_url', '$ip',
                                                                                       '$user_agent')
    expect(described_class.sanitize_sdk_event(event.merge(event: '$exception'))).to be_nil
  end

  it 'keeps only validated ad attribution on paid events at the final send boundary' do
    event = { event: 'paid_conversion', distinct_id: user.product_analytics_id,
              properties: { 'schema_version' => 1, 'channel' => 'billing', 'platform' => 'none',
                            'event_id' => SecureRandom.uuid, '$geoip_disable' => true,
                            'ad_source' => 'google_ads', 'ad_campaign_id' => '1234567890',
                            'gclid' => 'private-click-id' } }
    safe = described_class.sanitize_sdk_event(event)
    expect(safe[:properties]).to include('ad_source' => 'google_ads', 'ad_campaign_id' => '1234567890')
    expect(safe[:properties]).not_to have_key('gclid')
    expect(described_class.sanitize_sdk_event(event.deep_dup.tap do |invalid|
      invalid[:properties]['ad_campaign_id'] = 'private@example.com'
    end)).to be_nil
  end

  describe 'acquisition attribution' do
    let(:captured) { [] }

    before { allow(PostHog).to receive(:capture) { |attrs| captured << attrs } }

    def signup_properties
      described_class.capture(user: user, event: 'user_signed_up', channel: 'server',
                              properties: { auth_method: 'email' })
      captured.last[:properties]
    end

    it 'normalizes known sources, mediums and a slug campaign onto attribution events' do
      user.update!(utm_source: ' HN ', utm_medium: 'Newsletter', utm_campaign: 'Launch_Week-2')

      expect(signup_properties).to include('acquisition_source' => 'hackernews', 'acquisition_medium' => 'email',
                                           'acquisition_campaign' => 'launch_week-2')
    end

    it 'buckets unknown sources and mediums as other' do
      user.update!(utm_source: 'some-forum', utm_medium: 'inline-cta')

      expect(signup_properties).to include('acquisition_source' => 'other', 'acquisition_medium' => 'other')
    end

    it 'marks an account without campaign parameters as none' do
      expect(signup_properties).to include('acquisition_source' => 'none', 'acquisition_medium' => 'none')
      expect(signup_properties).not_to have_key('acquisition_campaign')
    end

    it 'drops a campaign that is not a plain slug' do
      user.update!(utm_source: 'newsletter', utm_campaign: 'private@example.com')

      expect(signup_properties).to include('acquisition_source' => 'newsletter')
      expect(signup_properties).not_to have_key('acquisition_campaign')
    end

    it 'adds no attribution to events outside the acquisition set' do
      user.update!(utm_source: 'reddit', utm_medium: 'social')

      described_class.capture(user: user, event: 'cloud_paywall_closed', channel: 'mobile',
                              properties: { result: 'cancelled' })

      expect(captured.last[:properties].keys.grep(/\Aacquisition_/)).to be_empty
    end

    it 'keeps only closed-list acquisition values at the final send boundary' do
      event = { event: 'trial_started', distinct_id: user.product_analytics_id,
                properties: { 'schema_version' => 1, 'channel' => 'billing', 'platform' => 'none',
                              'event_id' => SecureRandom.uuid, '$geoip_disable' => true,
                              'acquisition_source' => 'reddit', 'acquisition_medium' => 'social',
                              'acquisition_campaign' => 'spring' } }

      expect(described_class.sanitize_sdk_event(event.deep_dup)[:properties])
        .to include('acquisition_source' => 'reddit', 'acquisition_campaign' => 'spring')
      expect(described_class.sanitize_sdk_event(event.deep_dup.tap do |invalid|
        invalid[:properties]['acquisition_source'] = 'someone@example.com'
      end)).to be_nil
    end
  end
end
