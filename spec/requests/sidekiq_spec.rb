# frozen_string_literal: true

require 'rails_helper'

RSpec.describe '/sidekiq', type: :request do
  context 'when Dawarich is in self-hosted mode' do
    before do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
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
end
