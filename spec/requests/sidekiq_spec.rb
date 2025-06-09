# frozen_string_literal: true

require 'rails_helper'
require 'sidekiq/web'

RSpec.describe '/sidekiq', type: :request do
  before do
    # Allow any ENV key to be accessed and return nil by default
    allow(ENV).to receive(:[]).and_return(nil)

    # Stub Sidekiq::Web with a simple Rack app for testing
    allow(Sidekiq::Web).to receive(:call) do |_env|
      [200, { 'Content-Type' => 'text/html' }, ['Sidekiq Web UI']]
    end
  end

  context 'when Dawarich is in self-hosted mode' do
    before do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
      allow(ENV).to receive(:[]).with('SIDEKIQ_USERNAME').and_return(nil)
      allow(ENV).to receive(:[]).with('SIDEKIQ_PASSWORD').and_return(nil)
    end

    context 'when user is not authenticated' do
      it 'redirects to sign in page' do
        get sidekiq_url

        expect(response).to redirect_to('/users/sign_in')
      end
    end

    context 'when user is authenticated' do
      context 'when user is not admin' do
        before { sign_in create(:user) }

        it 'redirects to root page' do
          get sidekiq_url

          expect(response).to redirect_to(root_url)
        end

        it 'shows flash message' do
          get sidekiq_url

          expect(flash[:error]).to eq('You are not authorized to perform this action.')
        end
      end

      context 'when user is admin' do
        before { sign_in create(:user, :admin) }

        it 'renders a successful response' do
          get sidekiq_url

          expect(response).to be_successful
        end
      end
    end
  end

  context 'when Dawarich is not in self-hosted mode' do
    before do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      allow(ENV).to receive(:[]).with('SIDEKIQ_USERNAME').and_return(nil)
      allow(ENV).to receive(:[]).with('SIDEKIQ_PASSWORD').and_return(nil)
      Rails.application.reload_routes!
    end

    context 'when user is not authenticated' do
      it 'redirects to sign in page' do
        get sidekiq_url

        expect(response).to redirect_to('/users/sign_in')
      end
    end

    context 'when user is authenticated' do
      before { sign_in create(:user, :admin) }

      it 'redirects to root page' do
        get sidekiq_url

        expect(response).to redirect_to(root_url)
        expect(flash[:error]).to eq('You are not authorized to perform this action.')
      end
    end
  end

  context 'when SIDEKIQ_USERNAME and SIDEKIQ_PASSWORD are set' do
    before do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      allow(ENV).to receive(:[]).with('SIDEKIQ_USERNAME').and_return('admin')
      allow(ENV).to receive(:[]).with('SIDEKIQ_PASSWORD').and_return('password')
    end

    context 'when user is not authenticated' do
      it 'redirects to sign in page' do
        get sidekiq_url

        expect(response).to redirect_to('/users/sign_in')
      end
    end

    context 'when user is not admin' do
      before { sign_in create(:user) }

      it 'redirects to root page' do
        get sidekiq_url

        expect(response).to redirect_to(root_url)
        expect(flash[:error]).to eq('You are not authorized to perform this action.')
      end
    end

    context 'when user is admin' do
      before { sign_in create(:user, :admin) }

      it 'renders a successful response' do
        get sidekiq_url

        expect(response).to be_successful
      end
    end
  end
end
