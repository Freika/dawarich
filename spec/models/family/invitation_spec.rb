# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Family::Invitation, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:family) }
    it { is_expected.to belong_to(:invited_by).class_name('User') }
  end

  describe 'validations' do
    subject { build(:family_invitation) }

    it { is_expected.to validate_presence_of(:email) }
    it { is_expected.to allow_value('test@example.com').for(:email) }
    it { is_expected.not_to allow_value('invalid-email').for(:email) }
    it { is_expected.to validate_uniqueness_of(:token) }
    it { is_expected.to validate_presence_of(:status) }

    it 'validates token presence after creation' do
      invitation = build(:family_invitation, token: nil)
      invitation.save
      expect(invitation.token).to be_present
    end

    it 'validates expires_at presence after creation' do
      invitation = build(:family_invitation, expires_at: nil)
      invitation.save
      expect(invitation.expires_at).to be_present
    end
  end

  describe 'enums' do
    it { is_expected.to define_enum_for(:status).with_values(pending: 0, accepted: 1, expired: 2, cancelled: 3) }
  end

  describe 'scopes' do
    let(:family) { create(:family) }
    let(:pending_invitation) do
      create(:family_invitation, family: family, status: :pending, expires_at: 1.day.from_now)
    end
    let(:expired_invitation) { create(:family_invitation, family: family, status: :pending, expires_at: 1.day.ago) }
    let(:accepted_invitation) { create(:family_invitation, :accepted, family: family) }

    describe '.active' do
      it 'returns only pending and non-expired invitations' do
        expect(Family::Invitation.active).to include(pending_invitation)
        expect(Family::Invitation.active).not_to include(expired_invitation)
        expect(Family::Invitation.active).not_to include(accepted_invitation)
      end
    end
  end

  describe 'callbacks' do
    describe 'before_validation on create' do
      let(:invitation) { build(:family_invitation, token: nil, expires_at: nil) }

      it 'generates a token' do
        invitation.save
        expect(invitation.token).to be_present
        expect(invitation.token.length).to be > 20
      end

      it 'sets expiry date' do
        invitation.save
        expect(invitation.expires_at).to be_within(1.minute).of(Family::Invitation::EXPIRY_DAYS.days.from_now)
      end

      it 'does not override existing token' do
        custom_token = 'custom-token'
        invitation.token = custom_token
        invitation.save
        expect(invitation.token).to eq(custom_token)
      end

      it 'does not override existing expiry date' do
        custom_expiry = 3.days.from_now
        invitation.expires_at = custom_expiry
        invitation.save
        expect(invitation.expires_at).to be_within(1.second).of(custom_expiry)
      end
    end
  end

  describe '#expired?' do
    context 'when expires_at is in the future' do
      let(:invitation) { create(:family_invitation, expires_at: 1.day.from_now) }

      it 'returns false' do
        expect(invitation.expired?).to be false
      end
    end

    context 'when expires_at is in the past' do
      let(:invitation) { create(:family_invitation, expires_at: 1.day.ago) }

      it 'returns true' do
        expect(invitation.expired?).to be true
      end
    end
  end

  describe '#can_be_accepted?' do
    context 'when invitation is pending and not expired' do
      let(:invitation) { create(:family_invitation, status: :pending, expires_at: 1.day.from_now) }

      it 'returns true' do
        expect(invitation.can_be_accepted?).to be true
      end
    end

    context 'when invitation is pending but expired' do
      let(:invitation) { create(:family_invitation, status: :pending, expires_at: 1.day.ago) }

      it 'returns false' do
        expect(invitation.can_be_accepted?).to be false
      end
    end

    context 'when invitation is accepted' do
      let(:invitation) { create(:family_invitation, :accepted, expires_at: 1.day.from_now) }

      it 'returns false' do
        expect(invitation.can_be_accepted?).to be false
      end
    end

    context 'when invitation is cancelled' do
      let(:invitation) { create(:family_invitation, :cancelled, expires_at: 1.day.from_now) }

      it 'returns false' do
        expect(invitation.can_be_accepted?).to be false
      end
    end
  end

  describe 'constants' do
    it 'defines EXPIRY_DAYS' do
      expect(Family::Invitation::EXPIRY_DAYS).to eq(7)
    end
  end

  describe 'token uniqueness' do
    let(:family) { create(:family) }
    let(:user) { create(:user) }

    it 'ensures each invitation has a unique token' do
      invitation1 = create(:family_invitation, family: family, invited_by: user)
      invitation2 = create(:family_invitation, family: family, invited_by: user)

      expect(invitation1.token).not_to eq(invitation2.token)
    end
  end

  describe 'email format validation' do
    let(:invitation) { build(:family_invitation) }

    it 'accepts valid email formats' do
      valid_emails = ['test@example.com', 'user.name@domain.co.uk', 'user+tag@example.org']

      valid_emails.each do |email|
        invitation.email = email
        expect(invitation).to be_valid
      end
    end

    it 'rejects invalid email formats' do
      invalid_emails = ['invalid-email', '@example.com', 'user@', 'user space@example.com']

      invalid_emails.each do |email|
        invitation.email = email
        expect(invitation).not_to be_valid
        expect(invitation.errors[:email]).to be_present
      end
    end
  end
end
