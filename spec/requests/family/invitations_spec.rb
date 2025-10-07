# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Family::Invitations', type: :request do
  let(:user) { create(:user) }
  let(:family) { create(:family, creator: user) }
  let!(:membership) { create(:family_membership, user: user, family: family, role: :owner) }
  let(:invitation) { create(:family_invitation, family: family, invited_by: user) }

  before do
    stub_request(:any, 'https://api.github.com/repos/Freika/dawarich/tags')
      .to_return(status: 200, body: '[{"name": "1.0.0"}]', headers: {})
  end

  describe 'GET /family/invitations' do
    before { sign_in user }

    it 'shows pending invitations' do
      invitation # create the invitation
      get "/family/invitations"
      expect(response).to have_http_status(:ok)
    end

    context 'when user is not in the family' do
      let(:outsider) { create(:user) }

      before { sign_in outsider }

      it 'redirects to families index' do
        get "/family/invitations"
        expect(response).to redirect_to(new_family_path)
      end
    end

    context 'when not authenticated' do
      before { sign_out user }

      it 'redirects to login' do
        get "/family/invitations"
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'GET /invitations/:token (public invitation view)' do
    context 'when invitation is valid and pending' do
      it 'shows the invitation without authentication' do
        get "/invitations/#{invitation.token}"
        expect(response).to have_http_status(:ok)
      end
    end

    context 'when invitation is expired' do
      before { invitation.update!(expires_at: 1.day.ago) }

      it 'redirects with error message' do
        get "/invitations/#{invitation.token}"
        expect(response).to redirect_to(root_path)
        follow_redirect!
        expect(response.body).to include('This invitation has expired')
      end
    end

    context 'when invitation is not pending' do
      before { invitation.update!(status: :accepted) }

      it 'redirects with error message' do
        get "/invitations/#{invitation.token}"
        expect(response).to redirect_to(root_path)
        follow_redirect!
        expect(response.body).to include('This invitation is no longer valid')
      end
    end

    context 'when invitation does not exist' do
      it 'returns not found' do
        get '/invitations/invalid-token'
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST /family/invitations' do
    before { sign_in user }

    context 'with valid email' do
      let(:valid_params) do
        { family_invitation: { email: 'newuser@example.com' } }
      end

      it 'creates a new invitation' do
        expect do
          post "/family/invitations", params: valid_params
        end.to change(Family::Invitation, :count).by(1)
      end

      it 'redirects with success message' do
        post "/family/invitations", params: valid_params
        expect(response).to redirect_to(family_path)
        follow_redirect!
        expect(response.body).to include('Invitation sent successfully!')
      end
    end

    context 'with duplicate email' do
      let(:duplicate_params) do
        { family_invitation: { email: invitation.email } }
      end

      it 'does not create a duplicate invitation' do
        invitation # create the existing invitation
        expect do
          post "/family/invitations", params: duplicate_params
        end.not_to change(Family::Invitation, :count)
      end

      it 'redirects with error message' do
        invitation # create the existing invitation
        post "/family/invitations", params: duplicate_params
        expect(response).to redirect_to(family_path)
        follow_redirect!
        expect(response.body).to include('Invitation already sent to this email')
      end
    end

    context 'when user is not the owner' do
      before { membership.update!(role: :member) }

      it 'redirects due to authorization failure' do
        post "/family/invitations", params: {
          family_invitation: { email: 'test@example.com' }
        }
        expect(response).to have_http_status(:see_other)
        expect(flash[:alert]).to include('not authorized')
      end
    end

    context 'when user is not in the family' do
      let(:outsider) { create(:user) }

      before { sign_in outsider }

      it 'redirects to families index' do
        post "/family/invitations", params: {
          family_invitation: { email: 'test@example.com' }
        }
        expect(response).to redirect_to(new_family_path)
      end
    end

    context 'when not authenticated' do
      before { sign_out user }

      it 'redirects to login' do
        post "/family/invitations", params: {
          family_invitation: { email: 'test@example.com' }
        }
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'DELETE /family/invitations/:id' do
    before { sign_in user }

    it 'cancels the invitation' do
      delete "/family/invitations/#{invitation.token}"
      invitation.reload
      expect(invitation.status).to eq('cancelled')
    end

    it 'redirects with success message' do
      delete "/family/invitations/#{invitation.token}"
      expect(response).to redirect_to(family_path)
      follow_redirect!
      expect(response.body).to include('Invitation cancelled')
    end

    context 'when user is not the owner' do
      before { membership.update!(role: :member) }

      it 'redirects due to authorization failure' do
        delete "/family/invitations/#{invitation.token}"
        expect(response).to have_http_status(:see_other)
        expect(flash[:alert]).to include('not authorized')
      end
    end

    context 'when user is not in the family' do
      let(:outsider) { create(:user) }

      before { sign_in outsider }

      it 'redirects to families index' do
        delete "/family/invitations/#{invitation.token}"
        expect(response).to redirect_to(new_family_path)
      end
    end

    context 'when not authenticated' do
      before { sign_out user }

      it 'redirects to login' do
        delete "/family/invitations/#{invitation.token}"
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'invitation workflow integration' do
    let(:invitee) { create(:user) }

    it 'completes full invitation acceptance workflow' do
      # 1. Owner creates invitation
      sign_in user
      post "/family/invitations", params: {
        family_invitation: { email: invitee.email }
      }
      expect(response).to redirect_to(family_path)

      created_invitation = Family::Invitation.last
      expect(created_invitation.email).to eq(invitee.email)

      # 2. Invitee views public invitation page
      sign_out user
      get "/invitations/#{created_invitation.token}"
      expect(response).to have_http_status(:ok)

      # 3. Invitee accepts invitation
      sign_in invitee
      post accept_family_invitation_path(token: created_invitation.token)
      expect(response).to redirect_to(family_path)

      # 4. Verify invitee is now in family
      expect(invitee.reload.family).to eq(family)
      expect(created_invitation.reload.status).to eq('accepted')
    end
  end
end
