# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Settings → Geofencing', type: :request do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }
  let(:home) { create(:area, user:, name: 'Home') }
  let(:work) { create(:area, user:, name: 'Office') }
  let(:turbo) { { 'Accept' => 'text/vnd.turbo-stream.html' } }

  before { sign_in user }

  def page
    Nokogiri::HTML(response.body)
  end

  describe 'the geofencing page' do
    it 'lists real events, filtered by area, and highlights its tab' do
      create(:geofence_event, user:, area: home, event_type: :leave)
      create(:geofence_event, user:, area: work)
      create(:geofence_event, user:, area: home, synthetic: true)

      get settings_geofencing_path, params: { area_id: home.id }

      rows = page.css('[data-testid="geofence-event"]')
      expect(rows.size).to eq(1)
      expect(rows.first.text).to include('Home')
      expect(page.at_css('.tab-active')['href']).to eq(settings_geofencing_path)
    end

    it 'lists webhooks with their delivery status' do
      webhook = create(:webhook, user:, name: 'Home Assistant')
      create(:webhook_delivery, webhook:, geofence_event: create(:geofence_event, user:, area: home))

      get settings_geofencing_path

      expect(page.css('[data-testid="webhook"]').text).to include('Home Assistant')
      expect(page.css('[data-testid="event-delivery-status"]')).to be_present
    end

    context 'for a Lite user on cloud' do
      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
        user.update!(plan: :lite)
      end

      it 'offers an upgrade instead of webhooks and hides delivery status' do
        create(:geofence_event, user:, area: home)

        get settings_geofencing_path

        expect(page.at_css('[data-testid="webhooks-upgrade"]')).to be_present
        expect(page.css('[data-testid="webhook-form"]')).to be_empty
        expect(page.css('[data-testid="event-delivery-status"]')).to be_empty
      end

      it 'refuses to create a webhook' do
        post settings_webhooks_path, params: { webhook: { name: 'x', url: 'https://203.0.113.10/x' } }

        expect(Webhook.count).to eq(0)
        expect(response).to have_http_status(:see_other)
      end
    end
  end

  describe 'managing webhooks' do
    let(:attributes) { { name: 'Home Assistant', url: 'https://203.0.113.10/api/webhook/x', event_types: %w[0 1] } }

    it 'creates a webhook in place and shows its secret once' do
      post settings_webhooks_path, params: { webhook: attributes }, headers: turbo

      webhook = Webhook.sole
      expect(response.media_type).to eq('text/vnd.turbo-stream.html')
      expect(response.body).to include(webhook.secret)

      get settings_geofencing_path
      expect(response.body).not_to include(webhook.secret)
    end

    it 'shows validation errors without saving' do
      post settings_webhooks_path, params: { webhook: attributes.merge(url: 'ftp://x') }, headers: turbo

      expect(Webhook.count).to eq(0)
      expect(response.body).to include('webhook-form')
    end

    it 'updates, switches back on and deletes a webhook' do
      webhook = create(:webhook, user:, active: false, consecutive_failures: 5)

      patch settings_webhook_path(webhook), params: { webhook: { name: 'Renamed', active: '1' } }, headers: turbo
      expect(webhook.reload).to have_attributes(name: 'Renamed', active: true, consecutive_failures: 0)

      delete settings_webhook_path(webhook), headers: turbo
      expect(Webhook.exists?(webhook.id)).to be(false)
    end

    it 'sends a test and rotates the secret' do
      home
      webhook = create(:webhook, user:)

      expect { post test_settings_webhook_path(webhook), headers: turbo }
        .to have_enqueued_job(Webhooks::DeliverJob)

      old = webhook.secret
      post regenerate_secret_settings_webhook_path(webhook), headers: turbo
      expect(webhook.reload.secret).not_to eq(old)
      expect(response.body).to include(webhook.secret)
    end

    it 'shows recent deliveries and retries a failed one' do
      webhook = create(:webhook, user:)
      failed = create(:webhook_delivery, webhook:, status: :failure, error_message: 'HTTP 500')

      get settings_webhook_path(webhook)
      expect(page.css('[data-testid="webhook-delivery"]').text).to include('HTTP 500')
      expect(page.at_css('.tab-active')['href']).to eq(settings_geofencing_path)

      expect { post retry_delivery_settings_webhook_path(webhook, delivery_id: failed.id), headers: turbo }
        .to have_enqueued_job(Webhooks::DeliverJob).with(failed.id)
    end

    it 'never touches another user\'s webhook' do
      other = create(:webhook)

      delete settings_webhook_path(other), headers: turbo

      expect(Webhook.exists?(other.id)).to be(true)
    end
  end
end
