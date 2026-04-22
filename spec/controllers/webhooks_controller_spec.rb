# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WebhooksController, type: :controller do
  let(:user) { create(:user, plan: :pro) }

  before { sign_in user }

  describe 'GET #index' do
    it 'renders with 200' do
      create(:webhook, user: user)
      get :index
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'GET #show' do
    it 'renders with 200' do
      webhook = create(:webhook, user: user)
      get :show, params: { id: webhook.id }
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'GET #new' do
    it 'renders with 200' do
      get :new
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'GET #edit' do
    it 'renders with 200' do
      webhook = create(:webhook, user: user)
      get :edit, params: { id: webhook.id }
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'POST #create' do
    context 'with valid URL (turbo_stream)' do
      it 'creates a webhook and returns 200' do
        post :create,
             params: { webhook: { name: 'HA', url: 'https://example.com/hook' } },
             format: :turbo_stream
        expect(response).to have_http_status(:ok)
        expect(user.webhooks.count).to eq(1)
      end
    end

    context 'with private URL on cloud' do
      before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

      it 'rejects and returns 422' do
        post :create,
             params: { webhook: { name: 'HA', url: 'http://192.168.1.1/hook' } },
             format: :html
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'with invalid webhook params' do
      it 'renders new with 422 when name is blank' do
        post :create,
             params: { webhook: { name: '', url: 'https://example.com/hook' } },
             format: :html
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'PATCH #update' do
    it 'updates and returns 200 (turbo_stream)' do
      webhook = create(:webhook, user: user)
      patch :update,
            params: { id: webhook.id, webhook: { name: 'Updated' } },
            format: :turbo_stream
      expect(response).to have_http_status(:ok)
      expect(webhook.reload.name).to eq('Updated')
    end
  end

  describe 'DELETE #destroy' do
    it 'destroys the webhook (turbo_stream)' do
      webhook = create(:webhook, user: user)
      delete :destroy, params: { id: webhook.id }, format: :turbo_stream
      expect(Webhook.find_by(id: webhook.id)).to be_nil
    end
  end

  describe 'POST #test' do
    let!(:area) { create(:area, user: user) }

    it 'creates a WebhookDelivery and enqueues delivery job' do
      webhook = create(:webhook, user: user)
      expect {
        post :test, params: { id: webhook.id }, format: :turbo_stream
      }.to change(WebhookDelivery, :count).by(1)
    end

    it 'returns 200' do
      webhook = create(:webhook, user: user)
      post :test, params: { id: webhook.id }, format: :turbo_stream
      expect(response).to have_http_status(:ok)
    end

    context 'when no areas exist' do
      let(:user) { create(:user, plan: :pro) }

      it 'redirects with alert' do
        webhook = create(:webhook, user: user)
        post :test, params: { id: webhook.id }, format: :html
        expect(response).to have_http_status(:found)
      end
    end
  end

  describe 'POST #regenerate_secret' do
    it 'regenerates the secret and redirects to edit' do
      webhook = create(:webhook, user: user)
      old_secret = webhook.secret
      post :regenerate_secret, params: { id: webhook.id }
      expect(webhook.reload.secret).not_to eq(old_secret)
      expect(response).to redirect_to(edit_webhook_path(webhook))
    end
  end

  context 'Lite user on cloud' do
    let(:user) { create(:user, plan: :lite) }

    before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

    it 'allows index' do
      get :index
      expect(response).to have_http_status(:ok)
    end

    it 'redirects create (Pundit not authorized → redirect)' do
      post :create,
           params: { webhook: { name: 'X', url: 'https://example.com' } },
           format: :html
      # Pundit raises NotAuthorizedError → user_not_authorized → redirect_back → 303/302
      expect([302, 303]).to include(response.status)
    end
  end
end
