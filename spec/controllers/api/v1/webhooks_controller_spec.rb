# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::WebhooksController, type: :controller do
  let(:user) { create(:user, plan: :pro) }
  let(:lite_user) { create(:user, plan: :lite) }

  before { request.headers.merge!('Authorization' => "Bearer #{user.api_key}") }

  describe 'GET #index' do
    it 'lists user webhooks' do
      create(:webhook, user: user)
      get :index
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).length).to eq(1)
    end
  end

  describe 'POST #create' do
    it 'creates a webhook for Pro user' do
      post :create, params: { webhook: { name: 'HA', url: 'https://example.com/hook' } }
      expect(response).to have_http_status(:created)
    end

    it 'returns the generated secret in the response' do
      post :create, params: { webhook: { name: 'HA', url: 'https://example.com/hook' } }
      expect(JSON.parse(response.body)['secret']).to be_present
    end

    it 'rejects Lite user on cloud' do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      request.headers.merge!('Authorization' => "Bearer #{lite_user.api_key}")
      post :create, params: { webhook: { name: 'HA', url: 'https://example.com/hook' } }
      expect(response).to have_http_status(:forbidden)
    end

    it 'allows Lite user on self-hosted' do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
      request.headers.merge!('Authorization' => "Bearer #{lite_user.api_key}")
      post :create, params: { webhook: { name: 'HA', url: 'https://example.com/hook' } }
      expect(response).to have_http_status(:created)
    end

    it 'rejects invalid URL' do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      post :create, params: { webhook: { name: 'HA', url: 'http://192.168.1.1/hook' } }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'POST #test' do
    let(:webhook) { create(:webhook, user: user) }
    let!(:area) { create(:area, user: user) }

    it 'enqueues a synthetic enter delivery' do
      expect do
        post :test, params: { id: webhook.id }
      end.to change(WebhookDelivery, :count).by(1)
      expect(response).to have_http_status(:accepted)
    end
  end

  describe 'POST #regenerate_secret' do
    let(:webhook) { create(:webhook, user: user) }

    it 'returns a new secret' do
      old = webhook.secret
      post :regenerate_secret, params: { id: webhook.id }
      expect(webhook.reload.secret).not_to eq(old)
      expect(JSON.parse(response.body)['secret']).to eq(webhook.reload.secret)
    end
  end

  describe 'DELETE #destroy' do
    let(:webhook) { create(:webhook, user: user) }

    it 'deletes the webhook' do
      delete :destroy, params: { id: webhook.id }
      expect(response).to have_http_status(:no_content)
      expect(Webhook.find_by(id: webhook.id)).to be_nil
    end
  end
end
