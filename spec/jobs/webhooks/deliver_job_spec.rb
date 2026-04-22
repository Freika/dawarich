# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Webhooks::DeliverJob, type: :job do
  let(:user) { create(:user) }
  let(:area) { create(:area, user: user) }
  let(:webhook) { create(:webhook, user: user, url: 'https://example.com/hook', secret: 'shh') }
  let(:event) { create(:geofence_event, user: user, area: area) }
  let(:delivery) { create(:webhook_delivery, webhook: webhook, geofence_event: event, status: :pending) }

  describe '#perform' do
    context 'on 2xx response' do
      before do
        stub_request(:post, 'https://example.com/hook').to_return(status: 200, body: 'ok')
      end

      it 'marks delivery success' do
        described_class.new.perform(delivery.id)
        expect(delivery.reload).to be_status_success
        expect(delivery.response_status).to eq(200)
        expect(delivery.delivered_at).to be_present
      end

      it 'updates webhook last_success_at and resets consecutive_failures' do
        webhook.update!(consecutive_failures: 3)
        described_class.new.perform(delivery.id)
        expect(webhook.reload.last_success_at).to be_present
        expect(webhook.reload.consecutive_failures).to eq(0)
      end

      it 'sends HMAC signature header' do
        described_class.new.perform(delivery.id)
        expect(WebMock).to(have_requested(:post, 'https://example.com/hook')
          .with { |req| req.headers['X-Dawarich-Signature']&.start_with?('sha256=') })
      end

      it 'sends event-type and delivery-id headers' do
        described_class.new.perform(delivery.id)
        expect(WebMock).to(have_requested(:post, 'https://example.com/hook').with(
                             headers: {
                               'X-Dawarich-Event' => "geofence.#{event.event_type}",
                               'X-Dawarich-Delivery' => delivery.id.to_s
                             }
                           ))
      end
    end

    context 'on non-2xx' do
      before do
        stub_request(:post, 'https://example.com/hook').to_return(status: 500, body: 'err')
      end

      it 'marks delivery failure and increments consecutive_failures' do
        expect { described_class.new.perform(delivery.id) }.to raise_error(Webhooks::DeliverJob::DeliveryError)
        expect(delivery.reload.status_failure?).to be true
        expect(webhook.reload.consecutive_failures).to eq(1)
      end
    end

    context 'after 5 consecutive failures across deliveries' do
      before do
        stub_request(:post, 'https://example.com/hook').to_return(status: 500)
        webhook.update!(consecutive_failures: 4)
      end

      it 'deactivates the webhook' do
        expect { described_class.new.perform(delivery.id) }.to raise_error(Webhooks::DeliverJob::DeliveryError)
        expect(webhook.reload.active).to be false
      end
    end

    context 'when delivery no longer exists' do
      it 'does not raise' do
        delivery_id = delivery.id
        delivery.destroy
        expect { described_class.new.perform(delivery_id) }.not_to raise_error
      end
    end

    context 'when URL fails pre-send validation (DNS rebinding)' do
      # Create webhook and delivery BEFORE stubbing UrlValidator so model validation passes
      let!(:prepared_delivery) { delivery }

      before do
        # Simulate: URL was valid at creation, now resolves to a private IP
        allow(Webhooks::UrlValidator).to receive(:call).with(webhook.url).and_return(:private_address)
      end

      it 'does not send the HTTP request' do
        described_class.new.perform(prepared_delivery.id)
        expect(WebMock).not_to have_requested(:any, 'https://example.com/hook')
      end

      it 'marks the webhook inactive' do
        described_class.new.perform(prepared_delivery.id)
        expect(webhook.reload.active).to be false
      end

      it 'records the failure' do
        described_class.new.perform(prepared_delivery.id)
        expect(prepared_delivery.reload.status_failure?).to be true
        expect(prepared_delivery.reload.error_message).to match(/DNS|validation/i)
      end
    end

    context 'on network timeout' do
      before do
        stub_request(:post, 'https://example.com/hook').to_timeout
      end

      it 'records failure and re-raises for ActiveJob retry' do
        expect { described_class.new.perform(delivery.id) }.to raise_error(StandardError)
        expect(webhook.reload.consecutive_failures).to eq(1)
      end
    end
  end
end
