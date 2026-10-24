# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Webhooks::DeliverJob do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }
  let(:webhook) { create(:webhook, user:) }
  let(:delivery) { create(:webhook_delivery, webhook:) }
  let(:url) { webhook.url }

  def deliver
    perform_enqueued_jobs { described_class.perform_later(delivery.id) }
  end

  it 'posts a signed payload and records the success' do
    stub = stub_request(:post, url).to_return(status: 200, body: 'ok')
    webhook.update_columns(consecutive_failures: 2)

    deliver

    body = Webhooks::PayloadBuilder.call(delivery.geofence_event).to_json
    expect(stub.with(
             body:,
             headers: {
               'Content-Type' => 'application/json',
               'X-Dawarich-Event' => 'geofence.enter',
               'X-Dawarich-Delivery' => delivery.id.to_s,
               'X-Dawarich-Signature' => Webhooks::Signer.sign(body:, secret: webhook.secret)
             }
           )).to have_been_requested.once
    expect(delivery.reload).to have_attributes(status: 'success', response_status: 200, attempt_count: 1)
    expect(webhook.reload.consecutive_failures).to eq(0)
  end

  it 'retries a failing receiver five times, then records one failure' do
    stub = stub_request(:post, url).to_return(status: 500, body: 'boom')

    deliver

    expect(stub).to have_been_requested.times(5)
    expect(delivery.reload).to have_attributes(status: 'failure', response_status: 500, attempt_count: 5)
    expect(webhook.reload.consecutive_failures).to eq(1)
  end

  it 'treats a TLS error like any other failed attempt' do
    stub_request(:post, url).to_raise(OpenSSL::SSL::SSLError.new('certificate verify failed'))

    deliver

    expect(delivery.reload).to have_attributes(status: 'failure', attempt_count: 5)
    expect(delivery.error_message).to include('certificate verify failed')
  end

  it 'switches the webhook off and tells the user after five failed deliveries' do
    stub_request(:post, url).to_return(status: 503)
    webhook.update_columns(consecutive_failures: 4)

    expect { deliver }.to change { user.notifications.count }.by(1)
    expect(webhook.reload).to have_attributes(active: false, consecutive_failures: 5)
  end

  it 'connects to the address it validated' do
    webhook.update_columns(url: 'https://hooks.example.org/in')
    stub_host_addresses('hooks.example.org', '203.0.113.20')
    stub_request(:post, 'https://hooks.example.org/in').to_return(status: 204)
    pinned = []
    allow_any_instance_of(Net::HTTP).to receive(:ipaddr=).and_wrap_original do |original, address|
      pinned << address
      original.call(address)
    end

    deliver

    expect(pinned).to eq(['203.0.113.20'])
  end

  context 'on cloud' do
    before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

    it 'never requests a URL that now resolves to a private address' do
      webhook.update_columns(url: 'https://hooks.example.org/in')
      stub_host_addresses('hooks.example.org', '10.0.0.7')
      stub = stub_request(:post, 'https://hooks.example.org/in')

      deliver

      expect(stub).not_to have_been_requested
      expect(delivery.reload.status).to eq('failure')
      expect(webhook.reload.active).to be(false)
    end
  end
end
