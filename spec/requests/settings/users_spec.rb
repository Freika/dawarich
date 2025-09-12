# frozen_string_literal: true

require 'rails_helper'

RSpec.describe '/settings/users', type: :request do
  let(:valid_attributes) { { email: 'user@domain.com', password: '4815162342' } }
  let!(:admin) { create(:user, :admin) }

  context 'when Dawarich is in self-hosted mode' do
    before do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    end

    context 'when user is not authenticated' do
      it 'redirects to sign in page' do
        post settings_users_url, params: { user: valid_attributes }

        expect(response).to redirect_to(root_url)
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
        describe 'POST /create' do
          before { sign_in admin }

          context 'with valid parameters' do
            it 'creates a new User' do
              expect do
                post settings_users_url, params: { user: valid_attributes }
              end.to change(User, :count).by(1)

              expect(User.last.email).to eq(valid_attributes[:email])
              expect(User.last.valid_password?(valid_attributes[:password])).to be_truthy
            end

            it 'redirects to the created settings_user' do
              post settings_users_url, params: { user: valid_attributes }

              expect(response).to redirect_to(settings_users_url)
              expect(flash[:notice]).to eq('User was successfully created')
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

              expect(response).to have_http_status(:unprocessable_content)
            end
          end
        end

        describe 'PATCH /update' do
          let(:user) { create(:user) }

          before { sign_in admin }

          context 'with valid parameters' do
            let(:new_attributes) { { email: FFaker::Internet.email, password: '4815162342' } }

            it 'updates the requested user' do
              patch settings_user_url(user), params: { user: new_attributes }

              user.reload
              expect(user.email).to eq(new_attributes[:email])
              expect(user.valid_password?(new_attributes[:password])).to be_truthy
            end
          end
        end
      end
    end
  end

  context 'when Dawarich is not in self-hosted mode' do
    before do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      sign_in admin
    end

    describe 'GET /index' do
      it 'redirects to root page' do
        get settings_users_url

        expect(response).to redirect_to(root_url)
        expect(flash[:notice]).to eq('You are not authorized to perform this action.')
      end
    end

    describe 'POST /create' do
      it 'redirects to root page' do
        post settings_users_url, params: { user: valid_attributes }

        expect(response).to redirect_to(root_url)
        expect(flash[:notice]).to eq('You are not authorized to perform this action.')
      end
    end

    describe 'PATCH /update' do
      let(:user) { create(:user) }

      it 'redirects to root page' do
        patch settings_user_url(user), params: { user: valid_attributes }

        expect(response).to redirect_to(root_url)
        expect(flash[:notice]).to eq('You are not authorized to perform this action.')
      end
    end
  end
end
