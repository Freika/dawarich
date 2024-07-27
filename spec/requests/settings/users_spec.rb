# frozen_string_literal: true

require 'rails_helper'

RSpec.describe '/settings/users', type: :request do
  let(:valid_attributes) { { email: 'user@domain.com' } }

  context 'when user is not authenticated' do
    it 'redirects to sign in page' do
      post settings_users_url, params: { user: valid_attributes }

      expect(response).to redirect_to(new_user_session_url)
    end
  end

  context 'when user is authenticated' do
    context 'when user is not an admin' do
      before { sign_in create(:user) }

      it 'redirects to root page' do
        post settings_users_url, params: { user: valid_attributes }

        expect(response).to redirect_to(root_url)
      end
    end

    context 'when user is an admin' do
      let!(:admin) { create(:user, :admin) }

      before { sign_in admin }

      describe 'POST /create' do
        context 'with valid parameters' do
          it 'creates a new User' do
            expect do
              post settings_users_url, params: { user: valid_attributes }
            end.to change(User, :count).by(1)
          end

          it 'redirects to the created settings_user' do
            post settings_users_url, params: { user: valid_attributes }

            expect(response).to redirect_to(settings_url)
            expect(flash[:notice]).to eq("User was successfully created, email is #{valid_attributes[:email]}, password is \"password\".")
          end
        end

        context 'with invalid parameters' do
          let(:invalid_attributes) { { email: nil } }

          it 'does not create a new User' do
            expect do
              post settings_users_url, params: { user: invalid_attributes }
            end.to change(User, :count).by(0)
          end

          it 'renders a response with 422 status (i.e. to display the "new" template)' do
            post settings_users_url, params: { user: invalid_attributes }

            expect(response).to have_http_status(:unprocessable_entity)
          end
        end
      end
    end
  end
end
