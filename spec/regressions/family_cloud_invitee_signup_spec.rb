# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Family invitee signup on cloud', type: :request do
  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    stub_const('MANAGER_URL', 'https://manager.example.test')
    stub_const('ALLOW_EMAIL_PASSWORD_REGISTRATION', true)
    ActiveJob::Base.queue_adapter = :test
  end

  let(:owner) { create(:user, plan: :family, status: :trial, active_until: 7.days.from_now) }
  let(:family) { create(:family, creator: owner) }
  let!(:owner_membership) { create(:family_membership, :owner, user: owner, family: family) }
  let(:invitation) do
    create(:family_invitation, family: family, invited_by: owner, email: 'invitee@example.com')
  end

  def register_invitee
    post user_registration_path, params: {
      user: {
        email: invitation.email,
        password: 'password123456',
        password_confirmation: 'password123456'
      },
      invitation_token: invitation.token
    }
  end

  describe 'accepting an invitation by registering' do
    it 'does not divert the invitee to the subscription checkout' do
      register_invitee

      expect(response.location).not_to include('manager.example.test')
    end

    it 'lands the invitee on the family page' do
      register_invitee

      expect(response).to redirect_to(family_path)
    end

    it 'activates the invitee rather than demanding payment' do
      register_invitee

      expect(User.find_by(email: invitation.email)).to be_active
    end

    it 'signs the invitee in' do
      register_invitee
      follow_redirect!

      expect(response).to have_http_status(:ok)
    end

    it 'joins the invitee to the family' do
      expect { register_invitee }
        .to change { family.reload.members.count }.from(1).to(2)
    end

    it 'grants family access through the owner plan' do
      register_invitee

      expect(User.find_by(email: invitation.email).entitlements).to be_families
    end

    it 'puts the invitee on the pro plan' do
      register_invitee

      expect(User.find_by(email: invitation.email)).to be_pro
    end

    it 'marks the invitee active for the owner billing period' do
      register_invitee

      invitee = User.find_by(email: invitation.email)
      expect(invitee).to be_active
      expect(invitee.active_until).to be_within(1.second).of(owner.active_until)
    end

    it 'gives the invitee no subscription of their own' do
      register_invitee

      expect(User.find_by(email: invitation.email)).to be_sub_source_none
    end

    it 'lapses the invitee once the owner lapses' do
      register_invitee

      perform_enqueued_jobs(only: Families::MemberSyncJob) do
        owner.update!(status: :inactive, active_until: 1.day.ago)
      end

      invitee = User.find_by(email: invitation.email)
      expect(invitee).to be_inactive
      expect(invitee.active_until).to be_past
    end
  end

  describe 'a signup without an invitation' do
    it 'still goes to the subscription checkout' do
      post user_registration_path, params: {
        user: {
          email: 'stranger@example.com',
          password: 'password123456',
          password_confirmation: 'password123456'
        }
      }

      expect(response.location).to include('manager.example.test/checkout')
      expect(User.find_by(email: 'stranger@example.com')).to be_pending_payment
    end
  end

  describe 'a signup carrying an unusable invitation token' do
    it 'still goes to the subscription checkout' do
      invitation.update!(status: :cancelled)

      register_invitee

      expect(response.location).to include('manager.example.test/checkout')
      expect(User.find_by(email: invitation.email)).to be_pending_payment
    end
  end
end
