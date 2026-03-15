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

          it 'shows admin badge for admin users' do
            get settings_users_url

            expect(response.body).to include('Admin')
          end

          it 'shows last sign-in date when available' do
            create(:user, last_sign_in_at: Time.zone.parse('2026-01-15 10:30'))

            get settings_users_url

            expect(response.body).to include('2026')
          end

          it 'paginates results' do
            create_list(:user, 30)

            get settings_users_url

            # Should have pagination controls (kaminari)
            expect(response.body).to include('next')
          end

          it 'supports page parameter' do
            create_list(:user, 30)

            get settings_users_url, params: { page: 2 }

            expect(response).to have_http_status(:ok)
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

          context 'when toggling admin role' do
            it 'promotes a user to admin' do
              patch settings_user_url(user), params: { user: { admin: '1' } }

              expect(user.reload.admin?).to be true
            end

            it 'demotes an admin to regular user' do
              admin_user = create(:user, :admin)

              patch settings_user_url(admin_user), params: { user: { admin: '0' } }

              expect(admin_user.reload.admin?).to be false
            end

            it 'prevents removing admin from the last admin user' do
              # admin (from let!) is the only admin
              patch settings_user_url(admin), params: { user: { admin: '0' } }

              expect(admin.reload.admin?).to be true
              expect(flash[:alert]).to eq('Cannot remove admin role from the last admin user.')
            end

            it 'allows removing admin when other admins exist' do
              create(:user, :admin) # second admin

              patch settings_user_url(admin), params: { user: { admin: '0' } }

              expect(admin.reload.admin?).to be false
            end
          end

          context 'when toggling user status' do
            it 'disables an active user' do
              patch settings_user_url(user), params: { user: { status: 'inactive' } }

              expect(user.reload.status).to eq('inactive')
            end

            it 're-enables an inactive user' do
              user.update!(status: :inactive)

              patch settings_user_url(user), params: { user: { status: 'active' } }

              expect(user.reload.status).to eq('active')
            end

            it 'prevents disabling the last admin user' do
              patch settings_user_url(admin), params: { user: { status: 'inactive' } }

              expect(admin.reload.status).to eq('active')
              expect(flash[:alert]).to eq('Cannot disable the last admin user.')
            end
          end
        end

        describe 'GET /show' do
          let(:user) { create(:user, last_sign_in_at: 2.days.ago, current_sign_in_ip: '192.168.1.1', sign_in_count: 5) }

          before { sign_in admin }

          it 'renders the user detail page' do
            get settings_user_url(user)

            expect(response).to have_http_status(:ok)
            expect(response.body).to include(user.email)
          end

          it 'shows the user API key' do
            get settings_user_url(user)

            expect(response.body).to include(user.api_key)
          end

          it 'shows sign-in statistics' do
            get settings_user_url(user)

            expect(response.body).to include('192.168.1.1')
            expect(response.body).to include('5')
          end

          it 'shows data counts' do
            create_list(:point, 3, user: user)
            user.reload

            get settings_user_url(user)

            expect(response.body).to include(user.points_count.to_s)
          end
        end

        describe 'POST /regenerate_api_key' do
          let(:user) { create(:user) }

          before { sign_in admin }

          it 'regenerates the user API key' do
            old_key = user.api_key

            post regenerate_api_key_settings_user_url(user)

            expect(user.reload.api_key).not_to eq(old_key)
          end

          it 'redirects to user show page with notice' do
            post regenerate_api_key_settings_user_url(user)

            expect(response).to redirect_to(settings_user_url(user))
            expect(flash[:notice]).to eq('API key has been regenerated.')
          end
        end

        describe 'POST /send_password_reset' do
          let(:user) { create(:user) }

          before do
            sign_in admin
            allow(Devise).to receive(:mailer_sender).and_return('test@dawarich.app')
          end

          it 'sends a password reset email' do
            post send_password_reset_settings_user_url(user)

            expect(response).to redirect_to(settings_user_url(user))
            expect(flash[:notice]).to eq('Password reset email has been sent.')
          end

          it 'generates a reset password token for the user' do
            post send_password_reset_settings_user_url(user)

            expect(user.reload.reset_password_token).to be_present
          end
        end

        describe 'GET /index with search' do
          before { sign_in admin }

          it 'filters users by email' do
            create(:user, email: 'findme@example.com')
            create(:user, email: 'other@domain.com')

            get settings_users_url, params: { search: 'findme' }

            expect(response.body).to include('findme@example.com')
            expect(response.body).not_to include('other@domain.com')
          end

          it 'returns all users when search is blank' do
            user1 = create(:user)
            user2 = create(:user)

            get settings_users_url, params: { search: '' }

            expect(response.body).to include(user1.email)
            expect(response.body).to include(user2.email)
          end
        end

        describe 'PATCH /update_registration_settings' do
          before { sign_in admin }

          it 'disables registration' do
            patch update_registration_settings_settings_users_url,
                  params: { registration_enabled: '0' }

            expect(response).to redirect_to(settings_users_url)
            expect(DawarichSettings.registration_enabled?).to be false
          end

          it 'enables registration' do
            DawarichSettings.set_registration_enabled(false)

            patch update_registration_settings_settings_users_url,
                  params: { registration_enabled: '1' }

            expect(DawarichSettings.registration_enabled?).to be true
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
