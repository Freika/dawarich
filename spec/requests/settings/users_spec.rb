# frozen_string_literal: true

require 'rails_helper'

RSpec.describe '/settings/users', type: :request do
  before do
    sign_in create(:user)
  end

  describe 'POST /create' do
    context 'with valid parameters' do
      let(:valid_attributes) { { email: 'user@domain.com' } }

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
