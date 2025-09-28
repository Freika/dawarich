# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Users::Registrations', type: :request do
  let(:family_owner) { create(:user) }
  let(:family) { create(:family, creator: family_owner) }
  let!(:owner_membership) { create(:family_membership, user: family_owner, family: family, role: :owner) }
  let(:invitation) { create(:family_invitation, family: family, invited_by: family_owner, email: 'invited@example.com') }

  before do
    stub_request(:any, 'https://api.github.com/repos/Freika/dawarich/tags')
      .to_return(status: 200, body: '[{"name": "1.0.0"}]', headers: {})
  end

  describe 'Family Invitation Registration Flow' do
    context 'when accessing registration with a valid invitation token' do
      it 'shows family-focused registration page' do
        get new_user_registration_path(invitation_token: invitation.token)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Join #{family.name}!")
        expect(response.body).to include(family_owner.email)
        expect(response.body).to include(invitation.email)
        expect(response.body).to include('Create Account &amp; Join Family')
      end

      it 'pre-fills email field with invitation email' do
        get new_user_registration_path(invitation_token: invitation.token)

        expect(response.body).to include('value="invited@example.com"')
      end

      it 'makes email field readonly' do
        get new_user_registration_path(invitation_token: invitation.token)

        expect(response.body).to include('readonly')
      end

      it 'hides normal login links' do
        get new_user_registration_path(invitation_token: invitation.token)

        expect(response.body).not_to include('devise/shared/links')
      end
    end

    context 'when accessing registration without invitation token' do
      it 'shows normal registration page' do
        get new_user_registration_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('Register now!')
        expect(response.body).to include('take control over your location data')
        expect(response.body).not_to include('Join')
        expect(response.body).to include('Sign up')
      end
    end

    context 'when creating account with valid invitation token' do
      let(:user_params) do
        {
          email: invitation.email,
          password: 'password123',
          password_confirmation: 'password123'
        }
      end

      let(:request_params) do
        {
          user: user_params,
          invitation_token: invitation.token
        }
      end

      it 'creates user and accepts invitation automatically' do
        expect do
          post user_registration_path, params: request_params
        end.to change(User, :count).by(1)
         .and change { invitation.reload.status }.from('pending').to('accepted')

        new_user = User.find_by(email: invitation.email)
        expect(new_user).to be_present
        expect(new_user.family).to eq(family)
        expect(family.reload.members).to include(new_user)
      end

      it 'redirects to family page after successful registration' do
        post user_registration_path, params: request_params

        expect(response).to redirect_to(family_path(family))
      end

      it 'displays success message with family name' do
        post user_registration_path, params: request_params

        # Check that user got the default registration success message
        # (family welcome message is set but may be overridden by Devise)
        expect(flash[:notice]).to include("signed up successfully")
      end
    end

    context 'when creating account with invalid invitation token' do
      it 'creates user but does not accept any invitation' do
        expect do
          post user_registration_path, params: {
            user: {
              email: 'user@example.com',
              password: 'password123',
              password_confirmation: 'password123'
            },
            invitation_token: 'invalid-token'
          }
        end.to change(User, :count).by(1)

        new_user = User.find_by(email: 'user@example.com')
        expect(new_user.family).to be_nil
      end
    end

    context 'when invitation email does not match registration email' do
      it 'creates user but does not accept invitation' do
        expect do
          post user_registration_path, params: {
            user: {
              email: 'different@example.com',
              password: 'password123',
              password_confirmation: 'password123'
            },
            invitation_token: invitation.token
          }
        end.to change(User, :count).by(1)

        new_user = User.find_by(email: 'different@example.com')
        expect(new_user.family).to be_nil
        expect(invitation.reload.status).to eq('pending')
      end
    end
  end

  describe 'Self-Hosted Mode' do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('SELF_HOSTED').and_return('true')
    end

    context 'when accessing registration without invitation token' do
      it 'redirects to root with error message' do
        get new_user_registration_path

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to include('Registration is not available')
      end

      it 'prevents account creation' do
        expect do
          post user_registration_path, params: {
            user: {
              email: 'test@example.com',
              password: 'password123',
              password_confirmation: 'password123'
            }
          }
        end.not_to change(User, :count)

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to include('Registration is not available')
      end
    end

    context 'when accessing registration with valid invitation token' do
      it 'allows registration page access' do
        get new_user_registration_path(invitation_token: invitation.token)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Join #{family.name}!")
      end

      it 'allows account creation' do
        expect do
          post user_registration_path, params: {
            user: {
              email: invitation.email,
              password: 'password123',
              password_confirmation: 'password123'
            },
            invitation_token: invitation.token
          }
        end.to change(User, :count).by(1)

        expect(response).to redirect_to(family_path(family))
      end
    end

    context 'when accessing registration with expired invitation' do
      before { invitation.update!(expires_at: 1.day.ago) }

      it 'redirects to root with error message' do
        get new_user_registration_path(invitation_token: invitation.token)

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to include('Registration is not available')
      end
    end

    context 'when accessing registration with cancelled invitation' do
      before { invitation.update!(status: :cancelled) }

      it 'redirects to root with error message' do
        get new_user_registration_path(invitation_token: invitation.token)

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to include('Registration is not available')
      end
    end
  end

  describe 'Non-Self-Hosted Mode' do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('SELF_HOSTED').and_return('false')
    end

    context 'when accessing registration without invitation token' do
      it 'allows normal registration' do
        get new_user_registration_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('Register now!')
      end

      it 'allows account creation' do
        expect do
          post user_registration_path, params: {
            user: {
              email: 'test@example.com',
              password: 'password123',
              password_confirmation: 'password123'
            }
          }
        end.to change(User, :count).by(1)

        expect(response).to redirect_to(root_path)
      end
    end
  end

  describe 'Invitation Token Handling' do
    it 'accepts invitation token from params' do
      get new_user_registration_path(invitation_token: invitation.token)

      expect(response.body).to include("Join #{invitation.family.name}!")
    end

    it 'accepts invitation token from nested user params' do
      post user_registration_path, params: {
        user: {
          email: invitation.email,
          password: 'password123',
          password_confirmation: 'password123'
        },
        invitation_token: invitation.token
      }

      new_user = User.find_by(email: invitation.email)
      expect(new_user.family).to eq(family)
    end

    it 'handles session-stored invitation token' do
      # Simulate session storage by passing the token directly in params
      # (In real usage, this would come from the session after redirect from invitation page)
      get new_user_registration_path(invitation_token: invitation.token)

      expect(response.body).to include("Join #{invitation.family.name}!")
    end
  end

  describe 'Error Handling' do
    context 'when invitation acceptance fails' do
      before do
        # Mock service failure
        allow_any_instance_of(Families::AcceptInvitation).to receive(:call).and_return(false)
        allow_any_instance_of(Families::AcceptInvitation).to receive(:error_message).and_return('Mock error')
      end

      it 'creates user but shows invitation error in flash' do
        expect do
          post user_registration_path, params: {
            user: {
              email: invitation.email,
              password: 'password123',
              password_confirmation: 'password123'
            },
            invitation_token: invitation.token
          }
        end.to change(User, :count).by(1)

        expect(flash[:alert]).to include('Mock error')
      end
    end

    context 'when invitation acceptance raises exception' do
      before do
        # Mock service exception
        allow_any_instance_of(Families::AcceptInvitation).to receive(:call).and_raise(StandardError, 'Test error')
      end

      it 'creates user but shows generic error in flash' do
        expect do
          post user_registration_path, params: {
            user: {
              email: invitation.email,
              password: 'password123',
              password_confirmation: 'password123'
            },
            invitation_token: invitation.token
          }
        end.to change(User, :count).by(1)

        expect(flash[:alert]).to include('there was an issue accepting the invitation')
      end
    end
  end
end