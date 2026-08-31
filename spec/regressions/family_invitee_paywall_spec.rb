# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Family invitees are never sent to checkout', type: :request do
  before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

  let(:owner) { create(:user, plan: :family, status: :trial, active_until: 7.days.from_now) }
  let(:family) { create(:family, creator: owner) }
  let!(:owner_membership) { create(:family_membership, :owner, user: owner, family: family) }
  let(:invitation) do
    create(:family_invitation, family: family, invited_by: owner, email: invitee.email)
  end

  describe 'an abandoned-checkout user who gets invited' do
    let(:invitee) { create(:user, status: :pending_payment, skip_auto_trial: true) }

    it 'is taken to the invitation instead of the checkout on sign in' do
      post user_session_path, params: {
        user: { email: invitee.email, password: invitee.password },
        invitation_token: invitation.token
      }

      expect(response).to redirect_to(family_invitation_path(invitation.token))
    end

    it 'still goes to resume checkout when no invitation is waiting' do
      post user_session_path, params: {
        user: { email: invitee.email, password: invitee.password }
      }

      expect(response).to redirect_to(trial_resume_path)
    end
  end

  describe 'accepting the invitation' do
    let(:invitee) { create(:user, status: :pending_payment, skip_auto_trial: true) }

    before { sign_in invitee }

    it 'releases them from the payment gate' do
      post accept_family_invitation_path(token: invitation.token)

      expect(invitee.reload).to be_inactive
    end

    it 'puts them on lite so a lapsed owner drops them correctly' do
      post accept_family_invitation_path(token: invitation.token)

      expect(invitee.reload).to be_lite
    end

    it 'gives them family access' do
      post accept_family_invitation_path(token: invitation.token)

      expect(invitee.reload.entitlements.effective_plan).to eq(:family)
    end

    it 'unblocks the mobile API for them' do
      post accept_family_invitation_path(token: invitation.token)

      get '/api/v1/families/mine', params: { api_key: invitee.reload.api_key }

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'a paying subscriber who joins a family' do
    let(:invitee) { create(:user, plan: :pro, status: :active, active_until: 1.year.from_now, skip_auto_trial: true) }

    before { sign_in invitee }

    it 'keeps their own plan untouched' do
      post accept_family_invitation_path(token: invitation.token)

      expect(invitee.reload).to be_pro
      expect(invitee).to be_active
    end
  end
end
