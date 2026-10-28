# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Settings → Geofencing', type: :request do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }
  let(:home) { create(:place, :geofence, user:, name: 'Home') }
  let(:work) { create(:place, :geofence, user:, name: 'Office') }
  let(:turbo) { { 'Accept' => 'text/vnd.turbo-stream.html' } }

  before { sign_in user }

  def page
    Nokogiri::HTML(response.body)
  end

  describe 'the geofencing page' do
    it 'lists real events, filtered by place, and highlights its tab' do
      create(:geofence_event, user:, place: home, event_type: :leave)
      create(:geofence_event, user:, place: work)
      create(:geofence_event, user:, place: home, synthetic: true)

      get settings_geofencing_path, params: { place_id: home.id }

      rows = page.css('[data-testid="geofence-event"]')
      expect(rows.size).to eq(1)
      expect(rows.first.text).to include('Home')
      expect(page.at_css('.tab-active')['href']).to eq(settings_geofencing_path)
    end

    it 'shows event times on the clock the user chose' do
      user.update!(settings: user.settings.merge('time_format' => '12h'))
      create(:geofence_event, user:, place: home, occurred_at: Time.zone.parse('2026-10-20 15:05 UTC'))

      get settings_geofencing_path

      expect(page.at_css('[data-testid="geofence-event"] time').text.squish).to match(/3:05\s?PM/i)
    end

    it 'lists webhooks with their delivery status' do
      webhook = create(:webhook, user:, name: 'Home Assistant')
      create(:webhook_delivery, webhook:, geofence_event: create(:geofence_event, user:, place: home))

      get settings_geofencing_path

      expect(page.css('[data-testid="webhook"]').text).to include('Home Assistant')
      expect(page.css('[data-testid="event-delivery-status"]')).to be_present
    end

    it 'shows each webhook as active, failing or switched off with its last delivery' do
      create(:webhook, user:, name: 'Fresh')
      create(:webhook, user:, name: 'Working', last_success_at: 2.hours.ago)
      create(:webhook, user:, name: 'Failing', consecutive_failures: 2)
      create(:webhook, user:, name: 'Off', active: false, consecutive_failures: 5)

      get settings_geofencing_path

      rows = page.css('[data-testid="webhook"]').to_h do |row|
        badge = row.at_css('[data-testid="webhook-status"]')
        name = row.at_css('[data-testid="webhook-name"]').text
        [name, [badge.text.squish, badge['class'][/badge-(success|warning|ghost)/]]]
      end
      expect(rows).to eq(
        'Fresh' => %w[Active badge-success], 'Working' => %w[Active badge-success],
        'Failing' => %w[Failing badge-warning], 'Off' => ['Switched off', 'badge-ghost']
      )
      summaries = page.css('[data-testid="webhook"] summary').map { |summary| summary.text.squish }
      expect(summaries).to include(a_string_including('Nothing delivered yet'),
                                   a_string_including('Last delivered about 2 hours ago'),
                                   a_string_including('2 failed deliveries in a row'))
    end

    it 'counts deliveries that are still being retried' do
      webhook = create(:webhook, user:)
      event = create(:geofence_event, user:, place: home)
      create(:webhook_delivery, webhook:, status: :retrying, geofence_event: event)

      get settings_geofencing_path

      status = page.at_css('[data-testid="event-delivery-status"]').text.squish
      expect(status).to eq('1 in progress')
    end

    it 'sums delivered, failed and pending deliveries of one event' do
      event = create(:geofence_event, user:, place: home)
      create(:webhook_delivery, webhook: create(:webhook, user:), status: :success, geofence_event: event)
      create(:webhook_delivery, webhook: create(:webhook, user:), status: :failure, geofence_event: event)
      create(:webhook_delivery, webhook: create(:webhook, user:), status: :pending, geofence_event: event)

      get settings_geofencing_path

      status = page.at_css('[data-testid="event-delivery-status"]').text.squish
      expect(status).to eq('1 delivered, 1 failed, 1 in progress')
    end

    it 'shows a dash for an event no webhook was asked to send' do
      create(:geofence_event, user:, place: home)

      get settings_geofencing_path

      expect(page.at_css('[data-testid="event-delivery-status"]').text.squish).to eq('—')
    end

    it 'says when an event arrived too late to be sent' do
      create(:webhook, user:)
      create(:geofence_event, user:, place: home, occurred_at: 2.hours.ago, webhook_skip_reason: :late)
      create(:geofence_event, user:, place: work, occurred_at: 3.hours.ago, webhook_skip_reason: :throttled)

      get settings_geofencing_path

      statuses = page.css('[data-testid="event-delivery-status"]').map { |node| node.text.squish }
      expect(statuses).to eq(['Not sent: arrived more than 15 min late',
                              'Not sent: more than 60 enter and leave events in an hour'])
    end

    it 'explains how Home Assistant answers only where it applies' do
      create(:webhook, user:, name: 'HA', url: 'https://203.0.113.10/api/webhook/presence')
      create(:webhook, user:, name: 'n8n', url: 'https://203.0.113.11/webhook/presence')

      get settings_geofencing_path

      hint = '[data-testid="home-assistant-hint"]'
      rows = page.css('[data-testid="webhook"]').index_by { |row| row.at_css('[data-testid="webhook-name"]').text }
      expect(rows['HA'].at_css(hint)).to be_present
      expect(rows['n8n'].at_css(hint)).to be_nil
      expect(page.at_css("#webhook-form #{hint}")).to be_present
    end

    it 'tells cloud users how Home Assistant can accept webhooks from outside its network' do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      user.update!(plan: :pro, active_until: 1.year.from_now)

      get settings_geofencing_path
      cloud_hint = page.at_css('#webhook-form [data-testid="home-assistant-hint"]').text
      allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
      get settings_geofencing_path
      self_hosted_hint = page.at_css('#webhook-form [data-testid="home-assistant-hint"]').text

      expect(cloud_hint).to include('Nabu Casa')
      expect(self_hosted_hint).not_to include('Nabu Casa')
    end

    it 'marks a webhook that keeps failing' do
      create(:webhook, user:, name: 'Healthy')
      create(:webhook, user:, name: 'Broken', consecutive_failures: 3)
      create(:webhook, user:, name: 'Off', active: false, consecutive_failures: 5)

      get settings_geofencing_path

      statuses = page.css('[data-testid="webhook"]').to_h do |row|
        name = row.at_css('[data-testid="webhook-name"]').text.squish
        [name, row.at_css('[data-testid="webhook-status"]').text.squish]
      end
      expect(statuses).to eq('Healthy' => 'Active', 'Broken' => 'Failing', 'Off' => 'Switched off')
    end

    context 'for a Lite user on cloud' do
      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
        user.update!(plan: :lite)
      end

      it 'offers an upgrade instead of webhooks and hides delivery status' do
        create(:geofence_event, user:, place: home)

        get settings_geofencing_path

        expect(page.at_css('[data-testid="webhooks-upgrade"]')).to be_present
        expect(page.css('[data-testid="webhook-form"]')).to be_empty
        expect(page.css('[data-testid="event-delivery-status"]')).to be_empty
      end

      it 'still lets them delete a webhook they made before' do
        webhook = create(:webhook, user:)

        get settings_geofencing_path
        expect(page.css('[data-testid="webhook"]').text).to include(webhook.name)

        delete settings_webhook_path(webhook), headers: turbo
        expect(Webhook.exists?(webhook.id)).to be(false)
      end

      it 'hides events older than 12 months' do
        create(:geofence_event, user:, place: home, occurred_at: 13.months.ago)

        get settings_geofencing_path

        expect(page.css('[data-testid="geofence-event"]')).to be_empty
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

    it 'allows five test sends a minute on Dawarich Cloud, then asks to wait' do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      user.update!(plan: :pro, active_until: 1.year.from_now)
      home
      webhook = create(:webhook, user:)

      6.times { post test_settings_webhook_path(webhook), headers: turbo }

      expect(WebhookDelivery.count).to eq(5)
      expect(response).to have_http_status(:too_many_requests)
      expect(response.body).to include('Too many test sends')
    end

    it 'does not limit test sends on a self-hosted instance' do
      home
      webhook = create(:webhook, user:)

      6.times { post test_settings_webhook_path(webhook), headers: turbo }

      expect(WebhookDelivery.count).to eq(6)
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

    it 'retries only failed deliveries' do
      webhook = create(:webhook, user:)
      delivered = create(:webhook_delivery, webhook:, status: :success)

      expect { post retry_delivery_settings_webhook_path(webhook, delivery_id: delivered.id), headers: turbo }
        .not_to have_enqueued_job(Webhooks::DeliverJob)
      expect(response).to have_http_status(:not_found)
    end

    it 'never touches another user\'s webhook' do
      other = create(:webhook)

      delete settings_webhook_path(other), headers: turbo

      expect(Webhook.exists?(other.id)).to be(true)
    end
  end

  describe 'archived geofence labels', :archive do
    %i[en de es fr pl ca zh].each do |locale|
      it "marks archived geofences as paused in the filter and webhook forms in #{locale}" do
        home.update!(archived: true)
        webhook = create(:webhook, user:, place_ids: [home.id])
        labels = {
          en: 'paused while archived', de: 'pausiert, solange der Ort archiviert ist',
          es: 'en pausa mientras esté archivado', fr: 'en pause tant que le lieu est archivé',
          pl: 'wstrzymane, gdy miejsce jest zarchiwizowane', ca: 'en pausa mentre estigui arxivat', zh: '归档期间暂停'
        }

        get settings_geofencing_path, params: { locale: }

        expect(page.at_css("select[name='place_id'] option[value='#{home.id}']").text)
          .to include('Home', labels.fetch(locale))
        checkbox = page.at_css("#webhook_#{webhook.id} input[name='webhook[place_ids][]'][value='#{home.id}']")
        expect(checkbox.ancestors('label').text).to include('Home', labels.fetch(locale))
        expect(page.at_css("#webhook-form input[value='#{home.id}']")).to be_present
      end
    end
  end

  it 'shows a deleted place snapshot in the geofencing log', :place_retention do
    create(:geofence_event, user:, place: nil, place_name: 'Former home')

    get settings_geofencing_path

    expect(response).to have_http_status(:ok)
    expect(page.css('[data-testid="geofence-event"]').text).to include('Former home')
  end

  it 'shows a deleted place snapshot in webhook delivery history', :place_retention do
    webhook = create(:webhook, user:)
    event = create(:geofence_event, user:, place: nil, place_name: 'Former office')
    create(:webhook_delivery, webhook:, geofence_event: event)

    get settings_webhook_path(webhook)

    expect(response).to have_http_status(:ok)
    expect(page.css('[data-testid="webhook-delivery"]').text).to include('Former office')
  end
end
