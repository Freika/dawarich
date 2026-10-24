# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Webhooks', type: :request do
  let(:user) { create(:user) }
  let(:headers) { { 'Authorization' => "Bearer #{user.api_key}" } }
  let(:attributes) { { name: 'Home Assistant', url: 'https://203.0.113.10/api/webhook/x', event_types: [0] } }

  def json
    JSON.parse(response.body)
  end

  it 'creates a webhook and shows its secret once' do
    post '/api/v1/webhooks', params: { webhook: attributes }, headers:, as: :json

    expect(response).to have_http_status(:created)
    expect(json['secret']).to match(/\A\h{64}\z/)

    get '/api/v1/webhooks', headers: headers
    expect(json.sole).not_to have_key('secret')
    expect(json.sole).to include('name' => 'Home Assistant', 'event_types' => [0])

    get "/api/v1/webhooks/#{json.sole['id']}", headers: headers
    expect(json).not_to have_key('secret')
  end

  it 'updates, regenerates the secret and deletes' do
    webhook = create(:webhook, user:)
    old_secret = webhook.secret

    patch "/api/v1/webhooks/#{webhook.id}", params: { webhook: { name: 'Renamed' } }, headers:, as: :json
    expect(webhook.reload.name).to eq('Renamed')

    post "/api/v1/webhooks/#{webhook.id}/regenerate_secret", headers: headers
    expect(json['secret']).to eq(webhook.reload.secret).and(satisfy { |secret| secret != old_secret })

    delete "/api/v1/webhooks/#{webhook.id}", headers: headers
    expect(response).to have_http_status(:no_content)
    expect(Webhook.exists?(webhook.id)).to be(false)
  end

  it 'rejects an invalid URL' do
    post '/api/v1/webhooks', params: { webhook: attributes.merge(url: 'ftp://x') }, headers:, as: :json

    expect(response).to have_http_status(:unprocessable_content)
  end

  it 'sends a test delivery to that webhook only' do
    create(:area, user:)
    webhook = create(:webhook, user:)
    create(:webhook, user:)

    expect do
      post "/api/v1/webhooks/#{webhook.id}/test", headers: headers
    end.to have_enqueued_job(Webhooks::DeliverJob).exactly(:once)
    expect(response).to have_http_status(:accepted)
    expect(WebhookDelivery.sole.webhook).to eq(webhook)
  end

  it 'answers 422 to a test without any area' do
    post "/api/v1/webhooks/#{create(:webhook, user:).id}/test", headers: headers

    expect(response).to have_http_status(:unprocessable_content)
  end

  it 'never exposes another user\'s webhook' do
    get "/api/v1/webhooks/#{create(:webhook).id}", headers: headers

    expect(response).to have_http_status(:not_found)
  end

  context 'on cloud' do
    before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

    it 'refuses every webhook action but deletion to a Lite user' do
      user.update!(plan: :lite)
      webhook = create(:webhook, user:)
      base = "/api/v1/webhooks/#{webhook.id}"

      [
        -> { get '/api/v1/webhooks', headers: headers },
        -> { get base, headers: headers },
        -> { post '/api/v1/webhooks', params: { webhook: attributes }, headers: headers, as: :json },
        -> { patch base, params: { webhook: { name: 'x' } }, headers: headers, as: :json },
        -> { post "#{base}/test", headers: headers },
        -> { post "#{base}/regenerate_secret", headers: headers }
      ].each do |request|
        request.call
        expect(response).to have_http_status(:forbidden)
      end

      delete base, headers: headers
      expect(response).to have_http_status(:no_content)
    end

    it 'lets a Pro user manage webhooks' do
      user.update!(plan: :pro, active_until: 1.year.from_now)

      post '/api/v1/webhooks', params: { webhook: attributes }, headers: headers, as: :json

      expect(response).to have_http_status(:created)
    end

    it 'lets a Family user manage webhooks' do
      user.update!(plan: :family, active_until: 1.year.from_now)

      get '/api/v1/webhooks', headers: headers

      expect(response).to have_http_status(:ok)
    end
  end
end
