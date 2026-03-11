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

        expect(response).to redirect_to(new_user_session_path)
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
        describe 'GET /index' do
          before { sign_in admin }

          it 'does not include soft-deleted users' do
            deleted_user = create(:user)
            deleted_user.mark_as_deleted!

            get settings_users_url

            expect(response.body).not_to include(deleted_user.email)
          end

          it 'includes active users' do
            active_user = create(:user)

            get settings_users_url

            expect(response.body).to include(active_user.email)
          end
        end

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

        describe 'DELETE /destroy' do
          let(:user) { create(:user) }

          before { sign_in admin }

          context 'with a regular user' do
            it 'soft deletes the user' do
              user # force creation before count check
              expect do
                delete settings_user_url(user)
              end.to change(User, :count).by(-1)

              expect(user.reload.deleted?).to be true
            end

            it 'enqueues a background deletion job' do
              expect do
                delete settings_user_url(user)
              end.to have_enqueued_job(Users::DestroyJob).with(user.id)
            end

            it 'redirects to settings users page with notice' do
              delete settings_user_url(user)

              expect(response).to redirect_to(settings_users_url)
              expect(flash[:notice]).to eq(
                'User deletion has been initiated. The account will be fully removed shortly.'
              )
            end

            it 'immediately marks user as deleted' do
              delete settings_user_url(user)

              expect(user.reload.deleted_at).to be_present
            end
          end

          context 'when user is a family owner with members' do
            let(:family) { create(:family, creator: user) }
            let(:member) { create(:user) }

            before do
              create(:family_membership, user: user, family: family, role: :owner)
              create(:family_membership, user: member, family: family, role: :member)
            end

            it 'does not delete the user' do
              expect do
                delete settings_user_url(user)
              end.not_to(change { user.reload.deleted_at })
            end

            it 'returns unprocessable content with error message' do
              delete settings_user_url(user)

              expect(response).to have_http_status(:unprocessable_content)
              expect(flash[:alert]).to eq(
                'Cannot delete account while being owner of a family which has other members.'
              )
            end

            it 'does not enqueue deletion job' do
              expect do
                delete settings_user_url(user)
              end.not_to have_enqueued_job(Users::DestroyJob)
            end
          end

          context 'concurrent deletion attempts' do
            it 'returns not found for second deletion of already-deleted user' do
              # First deletion
              delete settings_user_url(user)
              expect(user.reload.deleted?).to be true

              # Second deletion attempt — default scope excludes the soft-deleted user,
              # so User.find raises RecordNotFound, which Rails rescues as 404
              delete settings_user_url(user)
              expect(response).to have_http_status(:not_found)
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
        expect(flash[:alert]).to eq('You are not authorized to perform this action.')
      end
    end

    describe 'POST /create' do
      it 'redirects to root page' do
        post settings_users_url, params: { user: valid_attributes }

        expect(response).to redirect_to(root_url)
        expect(flash[:alert]).to eq('You are not authorized to perform this action.')
      end
    end

    describe 'PATCH /update' do
      let(:user) { create(:user) }

      it 'redirects to root page' do
        patch settings_user_url(user), params: { user: valid_attributes }

        expect(response).to redirect_to(root_url)
        expect(flash[:alert]).to eq('You are not authorized to perform this action.')
      end
    end
  end
end
