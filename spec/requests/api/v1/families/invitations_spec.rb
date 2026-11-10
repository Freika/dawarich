# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Families::Invitations', type: :request do
  let(:owner) { create(:user) }
  let(:member) { create(:user) }
  let(:family) { create(:family, creator: owner) }
  let!(:owner_membership) { create(:family_membership, user: owner, family: family, role: :owner) }
  let!(:member_membership) { create(:family_membership, user: member, family: family, role: :member) }

  def json
    JSON.parse(response.body)
  end

  def api_call(verb, path, caller, body = nil)
    headers = { 'Authorization' => "Bearer #{caller.api_key}", 'Content-Type' => 'application/json' }
    send(verb, path, params: body&.to_json, headers: headers)
  end

  def make_cloud_family_live
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    owner.update!(plan: :family, active_until: 1.year.from_now)
    family.update!(access_until: 1.year.from_now)
  end

  def make_cloud_family_lapsed
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    owner.update!(plan: :family, active_until: 1.day.ago)
    family.update!(access_until: nil)
  end

  describe 'POST /api/v1/families/invitations' do
    def invite(caller, body)
      api_call(:post, '/api/v1/families/invitations', caller, body)
    end

    it 'creates the invitation for the owner and enqueues its email' do
      expect { invite(owner, { email: 'New@Example.com' }) }
        .to have_enqueued_job(Family::Invitations::SendingJob)

      expect(response).to have_http_status(:created)
      invitation = json['invitation']
      expect(invitation['id']).to eq(Family::Invitation.last.id)
      expect(invitation['email']).to eq('new@example.com')
      expect(invitation['expires_at']).to be_present
      expect(invitation['created_at']).to be_present
      expect(invitation).not_to have_key('token')
    end

    it 'builds the invitation url from the request host' do
      host! 'family.example.test'

      invite(owner, { email: 'new@example.com' })

      uri = URI.parse(json['invitation']['url'])
      expect(uri.host).to eq('family.example.test')
      expect(uri.path).to eq("/invitations/#{Family::Invitation.last.token}")
    end

    it 'returns owner_required for a member' do
      invite(member, { email: 'new@example.com' })

      expect(response).to have_http_status(:forbidden)
      expect(json['error']).to eq('owner_required')
    end

    it 'returns invitation_already_sent for a repeat' do
      invite(owner, { email: 'new@example.com' })
      invite(owner, { email: 'new@example.com' })

      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq('invitation_already_sent')
      expect(json['message']).to be_present
    end

    it 'returns user_already_in_family for an email that belongs to a family' do
      invite(owner, { email: member.email })

      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq('user_already_in_family')
    end

    it 'returns invalid_email without an email' do
      invite(owner, {})

      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq('invalid_email')
    end

    it 'returns invalid_email for a non-string email' do
      invite(owner, { email: { a: 1 } })

      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq('invalid_email')
    end

    it 'returns 404 for a user without a family' do
      invite(create(:user), { email: 'new@example.com' })

      expect(response).to have_http_status(:not_found)
    end

    context 'on cloud' do
      before { make_cloud_family_live }

      it 'returns family_full when every seat is taken' do
        3.times { |i| create(:family_invitation, family: family, invited_by: owner, email: "p#{i}@example.com") }

        invite(owner, { email: 'one-more@example.com' })

        expect(response).to have_http_status(:unprocessable_content)
        expect(json['error']).to eq('family_full')
      end

      it 'answers 429 rate_limited to the 11th invitation within an hour' do
        11.times { |i| invite(owner, { email: "rate#{i}@example.com" }) }

        expect(response).to have_http_status(:too_many_requests)
        expect(json).to eq('error' => 'rate_limited', 'message' => 'Too many invitations, try again later.')
      end

      it 'refuses an owner whose plan has lapsed with family_plan_required' do
        make_cloud_family_lapsed

        invite(owner, { email: 'new@example.com' })

        expect(response).to have_http_status(:forbidden)
        expect(json['error']).to eq('family_plan_required')
      end
    end

    it 'does not rate limit on self-hosted' do
      11.times { |i| invite(owner, { email: "rate#{i}@example.com" }) }

      expect(response).not_to have_http_status(:too_many_requests)
    end
  end

  describe 'DELETE /api/v1/families/invitations/:id' do
    let!(:invitation) { create(:family_invitation, family: family, invited_by: owner) }

    def revoke(caller, id)
      api_call(:delete, "/api/v1/families/invitations/#{id}", caller)
    end

    it 'cancels the invitation for the owner' do
      revoke(owner, invitation.id)

      expect(response).to have_http_status(:no_content)
      expect(invitation.reload).to be_cancelled
    end

    it 'cancels the invitation for a lapsed owner' do
      make_cloud_family_lapsed

      revoke(owner, invitation.id)

      expect(response).to have_http_status(:no_content)
      expect(invitation.reload).to be_cancelled
    end

    it 'returns owner_required for a member' do
      revoke(member, invitation.id)

      expect(response).to have_http_status(:forbidden)
      expect(json['error']).to eq('owner_required')
      expect(invitation.reload).to be_pending
    end

    it "returns invitation_not_found for another family's invitation" do
      other = create(:family_invitation)

      revoke(owner, other.id)

      expect(response).to have_http_status(:not_found)
      expect(json['error']).to eq('invitation_not_found')
      expect(other.reload).to be_pending
    end

    it 'returns invitation_not_found for an invitation that is no longer pending' do
      invitation.update!(status: :accepted)

      revoke(owner, invitation.id)

      expect(response).to have_http_status(:not_found)
      expect(json['error']).to eq('invitation_not_found')
    end
  end

  describe 'POST /api/v1/families/invitations/preview' do
    let(:invitee) { create(:user, email: 'invitee@example.com') }
    let!(:invitation) do
      create(:family_invitation, family: family, invited_by: owner, email: 'invitee@example.com')
    end

    def preview(caller, body)
      api_call(:post, '/api/v1/families/invitations/preview', caller, body)
    end

    it 'reads an invitation whose inviter account is gone as invalid' do
      owner.mark_as_deleted!

      preview(invitee, { token: invitation.token })

      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq('invitation_invalid')
    end

    it 'describes the invitation to the invitee' do
      preview(invitee, { token: invitation.token })

      expect(response).to have_http_status(:ok)
      expect(json['invitation']).to include(
        'family_name' => family.name,
        'invited_by_email' => owner.email,
        'email' => 'invitee@example.com',
        'plan_active' => true,
        'email_matches' => true
      )
      expect(json['invitation']['expires_at']).to be_present
    end

    it 'says email_matches false to a caller with another email' do
      preview(create(:user), { token: invitation.token })

      expect(response).to have_http_status(:ok)
      expect(json['invitation']['email_matches']).to be false
    end

    it 'says plan_active false for a lapsed family' do
      make_cloud_family_lapsed

      preview(invitee, { token: invitation.token })

      expect(json['invitation']['plan_active']).to be false
    end

    it 'returns invitation_not_found for an unknown token' do
      preview(invitee, { token: 'nope' })

      expect(response).to have_http_status(:not_found)
      expect(json['error']).to eq('invitation_not_found')
    end

    it 'returns invitation_not_found without a token' do
      preview(invitee, {})

      expect(response).to have_http_status(:not_found)
      expect(json['error']).to eq('invitation_not_found')
    end

    it 'returns invitation_invalid for an expired invitation' do
      invitation.update!(expires_at: 1.day.ago)

      preview(invitee, { token: invitation.token })

      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq('invitation_invalid')
    end

    it 'returns feature_disabled when the family toggle is off' do
      invitee.update!(settings: invitee.settings.merge('family_enabled' => false))

      preview(invitee, { token: invitation.token })

      expect(response).to have_http_status(:forbidden)
      expect(json['error']).to eq('feature_disabled')
    end

    it 'answers a caller in pending_payment' do
      invitee.update!(status: :pending_payment)

      preview(invitee, { token: invitation.token })

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'POST /api/v1/families/invitations/accept' do
    let(:invitee) { create(:user, email: 'invitee@example.com') }
    let!(:invitation) do
      create(:family_invitation, family: family, invited_by: owner, email: 'invitee@example.com')
    end

    def accept(caller, body)
      api_call(:post, '/api/v1/families/invitations/accept', caller, body)
    end

    it 'joins the caller and returns the mine body' do
      accept(invitee, { token: invitation.token })

      expect(response).to have_http_status(:ok)
      expect(json['family']['name']).to eq(family.name)
      expect(json['me']['user_id']).to eq(invitee.id)
      expect(json['me']['owner']).to be false
      expect(invitee.reload.family).to eq(family)
      expect(invitation.reload).to be_accepted
    end

    it 'returns email_mismatch for a caller with another email' do
      accept(create(:user), { token: invitation.token })

      expect(response).to have_http_status(:forbidden)
      expect(json['error']).to eq('email_mismatch')
    end

    it 'returns already_in_family for a caller in another family' do
      other_family = create(:family)
      create(:family_membership, user: invitee, family: other_family, role: :member)

      accept(invitee, { token: invitation.token })

      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq('already_in_family')
    end

    it 'returns invitation_invalid for a cancelled invitation' do
      invitation.update!(status: :cancelled)

      accept(invitee, { token: invitation.token })

      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq('invitation_invalid')
    end

    it 'returns invitation_not_found for an unknown token' do
      accept(invitee, { token: 'nope' })

      expect(response).to have_http_status(:not_found)
      expect(json['error']).to eq('invitation_not_found')
    end

    it 'returns feature_disabled when the family toggle is off' do
      invitee.update!(settings: invitee.settings.merge('family_enabled' => false))

      accept(invitee, { token: invitation.token })

      expect(response).to have_http_status(:forbidden)
      expect(json['error']).to eq('feature_disabled')
      expect(invitee.reload.family).to be_nil
    end

    context 'on cloud' do
      it 'returns plan_inactive for a lapsed family' do
        make_cloud_family_lapsed

        accept(invitee, { token: invitation.token })

        expect(response).to have_http_status(:unprocessable_content)
        expect(json['error']).to eq('plan_inactive')
      end

      it 'joins a caller who has no plan of their own' do
        make_cloud_family_live
        invitee.update!(plan: :lite, status: :inactive, active_until: nil)

        accept(invitee, { token: invitation.token })

        expect(response).to have_http_status(:ok)
        expect(json['lapsed']).to be false
        expect(invitee.reload.family).to eq(family)
      end

      it 'joins a caller in pending_payment, who is active afterwards' do
        make_cloud_family_live
        invitee.update!(plan: :lite, status: :pending_payment, active_until: nil)

        accept(invitee, { token: invitation.token })

        expect(response).to have_http_status(:ok)
        expect(invitee.reload).to be_active
      end
    end
  end
end
