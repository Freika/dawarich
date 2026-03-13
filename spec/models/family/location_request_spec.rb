# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Family::LocationRequest, type: :model do
  let(:family) { create(:family) }
  let(:requester) { family.creator }
  let(:target_user) { create(:user) }

  before do
    create(:family_membership, family: family, user: requester, role: :owner)
    create(:family_membership, family: family, user: target_user)
  end

  describe 'associations' do
    it { is_expected.to belong_to(:requester).class_name('User') }
    it { is_expected.to belong_to(:target_user).class_name('User') }
    it { is_expected.to belong_to(:family) }
  end

  describe 'validations' do
    subject { build(:family_location_request, requester: requester, target_user: target_user, family: family) }

    it { is_expected.to validate_presence_of(:requester_id) }
    it { is_expected.to validate_presence_of(:target_user_id) }
    it { is_expected.to validate_presence_of(:family_id) }

    it 'sets expires_at via before_validation if not provided' do
      request = build(:family_location_request, requester: requester, target_user: target_user, family: family, expires_at: nil)
      request.valid?
      expect(request.expires_at).to be_present
    end

    context 'when requester and target are the same user' do
      subject { build(:family_location_request, requester: requester, target_user: requester, family: family) }

      it 'is invalid' do
        expect(subject).not_to be_valid
        expect(subject.errors[:requester_id]).to include('cannot request your own location')
      end
    end

    context 'when valid' do
      it 'is valid with all required attributes' do
        expect(subject).to be_valid
      end
    end
  end

  describe 'enums' do
    it {
      is_expected.to define_enum_for(:status)
        .with_values(pending: 0, accepted: 1, declined: 2, expired: 3)
    }
  end

  describe 'scopes' do
    describe '.pending' do
      it 'returns only pending requests' do
        pending_request = create(:family_location_request, requester: requester, target_user: target_user, family: family, status: :pending)
        create(:family_location_request, requester: requester, target_user: target_user, family: family, status: :accepted)
        create(:family_location_request, requester: requester, target_user: target_user, family: family, status: :expired)

        expect(described_class.pending).to contain_exactly(pending_request)
      end
    end

    describe '.active' do
      it 'returns pending requests that have not expired' do
        active = create(:family_location_request, requester: requester, target_user: target_user, family: family,
                        status: :pending, expires_at: 1.hour.from_now)
        create(:family_location_request, requester: requester, target_user: target_user, family: family,
               status: :pending, expires_at: 1.hour.ago)
        create(:family_location_request, requester: requester, target_user: target_user, family: family,
               status: :accepted, expires_at: 1.hour.from_now)

        expect(described_class.active).to contain_exactly(active)
      end
    end
  end

  describe 'defaults' do
    subject { create(:family_location_request, requester: requester, target_user: target_user, family: family) }

    it 'sets suggested_duration to 24h' do
      expect(subject.suggested_duration).to eq('24h')
    end

    it 'sets expires_at to 24 hours from now by default' do
      expect(subject.expires_at).to be_within(5.seconds).of(24.hours.from_now)
    end

    it 'starts as pending' do
      expect(subject).to be_pending
    end
  end
end
